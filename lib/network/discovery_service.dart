import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core/models.dart';
import '../core/crypto.dart';

const int kDiscoveryPort = 47821;
const String kDiscoveryMagic = 'cliplink-discovery';
const int kDiscoveryIntervalSeconds = 3;
const int kPresenceTimeoutSeconds = 10;

/// UDP broadcast + multicast presence. No cloud service and no internet access
/// is involved; peers are discovered only on the current local network.
class DiscoveryService {
  DiscoveryService({
    required this.identity,
    required this.tcpPort,
    this.discoveryPort = kDiscoveryPort,
    required this.onPeersChanged,
    this.onError,
  });

  final LocalIdentity identity;
  final int tcpPort;
  final int discoveryPort;
  final void Function(List<PeerPresence> peers) onPeersChanged;
  final void Function(String message)? onError;

  static final InternetAddress multicastAddress = InternetAddress('239.255.77.66');
  static const MethodChannel _platformChannel = MethodChannel('app.cliplink/network');

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  Timer? _announceTimer;
  Timer? _pruneTimer;
  final Map<String, PeerPresence> _peers = <String, PeerPresence>{};
  List<String> _localAddresses = const <String>[];
  String? _lastSignature;
  bool _running = false;

  List<PeerPresence> get peers => List<PeerPresence>.unmodifiable(_peers.values);
  List<String> get localAddresses => _localAddresses;

  Future<void> start() async {
    if (_running) return;
    await _acquireMulticastLock();
    _localAddresses = await localIPv4Addresses();
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
    );
    _socket = socket;
    try {
      socket.broadcastEnabled = true;
    } catch (_) {}
    try {
      socket.multicastLoopback = true;
    } catch (_) {}
    try {
      socket.joinMulticast(multicastAddress);
    } catch (error) {
      onError?.call('组播不可用，已改用局域网广播');
    }
    _subscription = socket.listen(
      _handleSocketEvent,
      onError: (Object error) => onError?.call('网络发现异常：$error'),
    );
    _running = true;
    _announce();
    _announceTimer = Timer.periodic(
      const Duration(seconds: kDiscoveryIntervalSeconds),
      (_) => _announce(),
    );
    _pruneTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _prune(),
    );
  }

  Future<void> _acquireMulticastLock() async {
    if (!Platform.isAndroid) return;
    try {
      await _platformChannel.invokeMethod<void>('acquireMulticastLock');
    } on MissingPluginException {
      // The app still works with broadcast discovery when the platform-side
      // helper is unavailable.
    } catch (_) {}
  }

  Future<void> updateAdvertisement() async {
    // Identity name is stored in a mutable object; callers update it before
    // invoking this. The TCP port is fixed for the server's lifetime.
    await refreshInterfaces();
    _announce();
  }

  Future<void> refreshInterfaces() async {
    _localAddresses = await localIPv4Addresses();
  }

  void _handleSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final socket = _socket;
    if (socket == null) return;
    while (true) {
      final datagram = socket.receive();
      if (datagram == null) break;
      try {
        _handlePacket(datagram);
      } catch (_) {
        // Discovery packets are untrusted; ignore malformed input.
      }
    }
  }

  void _handlePacket(Datagram datagram) {
    if (datagram.data.length > 2048) return;
    final decoded = jsonDecode(utf8.decode(datagram.data, allowMalformed: true));
    if (decoded is! Map) return;
    final map = decoded.cast<String, Object?>();
    if (map['magic'] != kDiscoveryMagic || map['v'] != protocolVersion) return;
    final id = map['id'];
    if (id is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(id) ||
        id == identity.id) {
      return;
    }
    final port = (map['port'] as num?)?.toInt();
    if (port == null || port < 1 || port > 65535) return;
    if (map['bye'] == true) {
      if (_peers.remove(id) != null) _notify(force: true);
      return;
    }
    final rawName = map['name'];
    if (rawName is! String) return;
    final name = cleanDeviceName(rawName);
    final platform = map['platform'] is String
        ? (map['platform']! as String)
        : 'unknown';
    final advertised = <String>[];
    final rawAddresses = map['ips'];
    if (rawAddresses is List) {
      for (final value in rawAddresses) {
        if (value is String && InternetAddress.tryParse(value) != null) {
          advertised.add(value);
        }
      }
    }
    final source = datagram.address.address;
    if (InternetAddress.tryParse(source) != null &&
        !advertised.contains(source) &&
        !source.startsWith('127.')) {
      advertised.insert(0, source);
    }
    if (advertised.isEmpty) return;
    final peer = PeerPresence(
      id: id,
      name: name,
      platform: platform,
      addresses: advertised,
      port: port,
      lastSeen: DateTime.now(),
    );
    final previous = _peers[id];
    _peers[id] = peer;
    if (previous == null ||
        previous.name != peer.name ||
        previous.platform != peer.platform ||
        previous.port != peer.port ||
        !_sameAddresses(previous.addresses, peer.addresses)) {
      _notify(force: true);
    }
  }

  bool _sameAddresses(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _announce() {
    if (!_running) return;
    final socket = _socket;
    if (socket == null) return;
    final packet = utf8.encode(
      jsonEncode(<String, Object?>{
        'magic': kDiscoveryMagic,
        'v': protocolVersion,
        'id': identity.id,
        'name': cleanDeviceName(identity.name),
        'platform': identity.platform,
        'port': tcpPort,
        'ips': _localAddresses,
        'ts': DateTime.now().millisecondsSinceEpoch,
      }),
    );
    try {
      socket.send(packet, InternetAddress('255.255.255.255'), discoveryPort);
    } catch (_) {}
    try {
      socket.send(packet, multicastAddress, discoveryPort);
    } catch (_) {}
  }

  void _prune() {
    if (_peers.isEmpty) return;
    final cutoff = DateTime.now().subtract(
      const Duration(seconds: kPresenceTimeoutSeconds),
    );
    final removed = _peers.entries
        .where((entry) => entry.value.lastSeen.isBefore(cutoff))
        .map((entry) => entry.key)
        .toList();
    for (final id in removed) {
      _peers.remove(id);
    }
    if (removed.isNotEmpty) _notify(force: true);
  }

  void _notify({bool force = false}) {
    final peersList = _peers.values.toList()
      ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    final signature = peersList
        .map(
          (peer) =>
              '${peer.id}:${peer.name}:${peer.platform}:${peer.port}:${peer.addresses.join(',')}',
        )
        .join('|');
    if (!force && signature == _lastSignature) return;
    _lastSignature = signature;
    onPeersChanged(List<PeerPresence>.unmodifiable(peersList));
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _announceTimer?.cancel();
    _pruneTimer?.cancel();
    _announceTimer = null;
    _pruneTimer = null;
    final socket = _socket;
    if (socket != null) {
      try {
        final farewell = utf8.encode(
          jsonEncode(<String, Object?>{
            'magic': kDiscoveryMagic,
            'v': protocolVersion,
            'id': identity.id,
            'bye': true,
          }),
        );
        socket.send(farewell, InternetAddress('255.255.255.255'), discoveryPort);
      } catch (_) {}
      try {
        socket.leaveMulticast(multicastAddress);
      } catch (_) {}
    }
    await _subscription?.cancel();
    _subscription = null;
    socket?.close();
    _socket = null;
    if (Platform.isAndroid) {
      try {
        await _platformChannel.invokeMethod<void>('releaseMulticastLock');
      } on MissingPluginException {
        // Ignore.
      } catch (_) {}
    }
  }

  static Future<List<String>> localIPv4Addresses() async {
    final addresses = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: true,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final value = address.address;
          if (!value.startsWith('127.') && !addresses.contains(value)) {
            addresses.add(value);
          }
        }
      }
    } catch (_) {}
    addresses.sort((a, b) => _addressRank(a).compareTo(_addressRank(b)));
    return addresses;
  }

  static int _addressRank(String address) {
    if (address.startsWith('192.168.')) return 0;
    if (address.startsWith('10.')) return 1;
    if (address.startsWith('172.')) return 2;
    if (address.startsWith('169.254.')) return 9;
    return 5;
  }
}
