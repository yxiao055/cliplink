import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'core/crypto.dart';
import 'core/local_store.dart';
import 'core/models.dart';
import 'network/discovery_service.dart';
import 'network/pairing_code.dart';
import 'network/peer_connection.dart';
import 'network/peer_server.dart';
import 'services/clipboard_service.dart';

class OutgoingPairingState {
  OutgoingPairingState({
    required this.peerId,
    required this.name,
    required this.platform,
    required this.isCodeMode,
  });

  final String peerId;
  final String name;
  final String platform;
  final bool isCodeMode;
  final PairingCancellation cancellation = PairingCancellation();
  String? sas;
  String? error;
  bool finished = false;

  String? get formattedSas {
    final value = sas;
    if (value == null) return null;
    return '${value.substring(0, 3)} ${value.substring(3)}';
  }
}

class IncomingPairingState {
  IncomingPairingState({
    required this.peerId,
    required this.name,
    required this.platform,
    required this.sas,
  });

  final String peerId;
  final String name;
  final String platform;
  final String sas;

  String get formattedSas => '${sas.substring(0, 3)} ${sas.substring(3)}';
}

class PairedDeviceView {
  PairedDeviceView({
    required this.peer,
    required this.connected,
    required this.online,
    required this.connecting,
    this.address,
    this.port,
  });

  final PairedPeer peer;
  final bool connected;
  final bool online;
  final bool connecting;
  final String? address;
  final int? port;
}

class AppController extends ChangeNotifier {
  AppController({Directory? dataRoot}) : _providedRoot = dataRoot;

  static const String appVersion = '1.0.0';
  static const int defaultPeerPort = 47820;

  final Directory? _providedRoot;
  AppPaths? _paths;
  late IdentityStore _identityStore;
  late SettingsStore _settingsStore;
  late PeerStore _peerStore;
  HistoryStore? _historyStore;

  LocalIdentity? identity;
  AppSettings? settings;

  final Map<String, PairedPeer> _peers = <String, PairedPeer>{};
  final Map<String, PeerPresence> _presence = <String, PeerPresence>{};
  final Map<String, PeerConnection> _connections = <String, PeerConnection>{};
  final Set<String> _connecting = <String>{};

  PeerServer? _server;
  DiscoveryService? _discovery;
  ClipboardService? _clipboard;
  final PairingCodeStore _pairingCodes = PairingCodeStore();
  final StreamController<String> _notices = StreamController<String>.broadcast();
  final Map<String, DateTime> _seenIncoming = <String, DateTime>{};

  Timer? _autoConnectTimer;
  Timer? _pairingCodeTimer;
  Timer? _incomingPairingTimer;
  Timer? _networkRefreshTimer;
  Completer<bool>? _incomingDecision;
  IncomingPairingState? _incomingPairing;
  OutgoingPairingState? _outgoingPairing;

  List<String> _localAddresses = const <String>[];
  int _serverPort = 0;
  bool _loading = true;
  bool _initialized = false;
  bool _servicesStarted = false;
  bool _startingServices = false;
  bool _stopping = false;
  bool _foreground = true;
  bool _clipboardRunning = false;
  bool _syncPaused = false;
  bool _disposed = false;
  String? fatalError;
  String? networkError;
  ClipItem? lastClip;
  DateTime? lastSyncAt;

  List<ClipItem>? _previewHistory;

  Stream<String> get notices => _notices.stream;
  bool get isLoading => _loading;
  bool get isReady => _initialized && !_loading;
  bool get needsOnboarding =>
      _initialized && !(settings?.onboardingDone ?? false);
  bool get syncPaused => _syncPaused;
  bool get isOnline => _connections.isNotEmpty;
  bool get isDiscovering => _discovery != null;
  bool get isNetworkRunning => _serverPort > 0 && !_stopping;
  int get connectedCount => _connections.length;
  int get nearbyCount => nearbyDevices.length;
  String get platform => identity?.platform ?? Platform.operatingSystem;
  String get deviceName => identity?.name ?? '';
  List<String> get localAddresses => List<String>.unmodifiable(_localAddresses);
  String? get bestLocalAddress =>
      _localAddresses.isEmpty ? null : _localAddresses.first;
  String get localEndpoint {
    final address = bestLocalAddress;
    if (address == null || _serverPort == 0) return '未连接局域网';
    return '$address:$_serverPort';
  }

  /// Every advertised address with the listening port. Useful when the device
  /// has multiple adapters (Wi-Fi, Ethernet, VPN).
  List<String> get localEndpoints {
    if (_serverPort == 0) return const <String>[];
    return _localAddresses
        .map((address) => '$address:$_serverPort')
        .toList(growable: false);
  }

  String get endpointNotice {
    if (_serverPort == 0) return '局域网服务尚未启动';
    if (bestLocalAddress == null) return '未加入 Wi-Fi / 局域网';
    return localEndpoint;
  }

  PairingCodeEntry? get pairingCode => _pairingCodes.active;
  OutgoingPairingState? get outgoingPairing => _outgoingPairing;
  IncomingPairingState? get incomingPairing => _incomingPairing;
  List<ClipItem> get history =>
      _previewHistory ?? _historyStore?.items ?? const <ClipItem>[];
  ClipboardService? get clipboardService => _clipboard;

  List<PairedDeviceView> get pairedDevices {
    final values = _peers.values.map((peer) {
      final presence = _presence[peer.id];
      final connection = _connections[peer.id];
      final address = presence?.addresses.isNotEmpty == true
          ? presence!.addresses.first
          : peer.lastAddress;
      return PairedDeviceView(
        peer: peer,
        connected: connection != null && !connection.isClosed,
        online: presence != null || connection != null,
        connecting: _connecting.contains(peer.id),
        address: address,
        port: presence?.port ?? peer.lastPort,
      );
    }).toList();
    values.sort((a, b) {
      if (a.connected != b.connected) return a.connected ? -1 : 1;
      if (a.online != b.online) return a.online ? -1 : 1;
      return a.peer.name.toLowerCase().compareTo(b.peer.name.toLowerCase());
    });
    return values;
  }

  List<PeerPresence> get nearbyDevices {
    final values = _presence.values
        .where((presence) => !_peers.containsKey(presence.id))
        .toList();
    values.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return values;
  }

  /// Loads all local state. Network services start separately so the first-run
  /// screen can be shown before iOS asks for local-network permission.
  Future<void> bootstrap() async {
    try {
      final override = Platform.environment['CLIPLINK_DATA_DIR']?.trim();
      final root = _providedRoot ??
          (override != null && override.isNotEmpty
              ? Directory(override)
              : await getApplicationSupportDirectory());
      _paths = AppPaths(root);
      await _paths!.ensure();
      _identityStore = IdentityStore(_paths!);
      _settingsStore = SettingsStore(_paths!);
      _peerStore = PeerStore(_paths!);
      identity = await _identityStore.loadOrCreate(Platform.operatingSystem);
      settings = await _settingsStore.load(identity!.platform);
      _peers.addAll(await _peerStore.load());
      _historyStore = HistoryStore(_paths!);
      await _historyStore!.load();
      _localAddresses = await DiscoveryService.localIPv4Addresses();
      _initialized = true;
    } catch (error, stackTrace) {
      fatalError = '初始化失败：$error';
      debugPrint('$error\n$stackTrace');
    } finally {
      _loading = false;
      _safeNotify();
    }
  }

  /// Called once the app shell is mounted. Starting here ensures platform
  /// channels and permission prompts have a UI to attach to.
  Future<void> startServicesIfNeeded() async {
    if (!_initialized || needsOnboarding || _servicesStarted) return;
    await startServices();
  }

  Future<void> completeOnboarding({required String name}) async {
    if (!_initialized) return;
    identity!.name = cleanDeviceName(name);
    await _identityStore.save(identity!);
    settings!.onboardingDone = true;
    await _settingsStore.save(settings!);
    _safeNotify();
    await startServices();
  }

  Future<void> startServices() async {
    if (_servicesStarted || _startingServices || _stopping) return;
    _startingServices = true;
    _servicesStarted = true;
    try {
      _localAddresses = await DiscoveryService.localIPv4Addresses();
      _server = PeerServer(
        identity: identity!,
        findPaired: (id) => _peers[id],
        approvePairing: _approveIncomingPair,
        onPeerPaired: _savePeer,
        onClip: (item) async {
          await _handleRemoteClip(item.originName, item);
        },
        onAuthenticated: _registerConnection,
        onConnectionClosed: _handleConnectionClosed,
        pairingCodes: _pairingCodes,
        onPairingCodeConsumed: _clearPairingCodeAfterUse,
        onLog: (message) => debugPrint('[net] $message'),
        preferredPort: defaultPeerPort,
      );
      await _server!.start();
      _serverPort = _server!.port;
      networkError = null;
    } catch (error) {
      networkError = '无法启动局域网服务：$error';
      _notice(networkError!);
      _server = null;
      _serverPort = 0;
    }
    try {
      if (settings!.discoverable) {
        await _startDiscovery();
      }
      _clipboard = ClipboardService(
        identity: identity!,
        onCaptured: _onLocalClipboard,
        onError: _notice,
      );
      if (settings!.autoMonitor) {
        await _startClipboardMonitoring();
      }
      _autoConnectTimer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => _autoConnectTick(),
      );
      _networkRefreshTimer = Timer.periodic(
        const Duration(seconds: 20),
        (_) => _refreshNetwork(),
      );
    } catch (error, stackTrace) {
      debugPrint('Service startup failed: $error\n$stackTrace');
      _notice('部分服务启动失败：$error');
    } finally {
      _startingServices = false;
      _safeNotify();
      if (!_stopping) {
        Future<void>.delayed(const Duration(seconds: 1), _autoConnectTick);
      }
    }
  }

  Future<void> _startDiscovery() async {
    if (_discovery != null || _server == null) return;
    final service = DiscoveryService(
      identity: identity!,
      tcpPort: _server!.port,
      onPeersChanged: (peers) {
        if (_disposed) return;
        _presence
          ..clear()
          ..addEntries(peers.map((peer) => MapEntry(peer.id, peer)));
        _safeNotify();
        _autoConnectTick();
      },
      onError: (message) {
        if (_disposed) return;
        networkError = message;
        _safeNotify();
      },
    );
    try {
      await service.start();
      _discovery = service;
      _localAddresses = service.localAddresses;
      networkError = null;
    } catch (error) {
      networkError = '局域网发现不可用：$error';
      _notice('$networkError，可使用配对码连接');
    }
  }

  Future<void> _stopDiscovery() async {
    final discovery = _discovery;
    _discovery = null;
    _presence.clear();
    await discovery?.stop();
    _safeNotify();
  }

  Future<void> _startClipboardMonitoring() async {
    final clipboard = _clipboard;
    if (clipboard == null || _clipboardRunning) return;
    if (clipboardMonitoringIsForegroundOnly && !_foreground) return;
    _clipboardRunning = true;
    try {
      await clipboard.start();
    } catch (error) {
      _clipboardRunning = false;
      _notice('剪贴板监听启动失败：$error');
    }
  }

  Future<void> _stopClipboardMonitoring() async {
    _clipboardRunning = false;
    await _clipboard?.stop();
  }

  void _onLocalClipboard(ClipItem item) {
    unawaited(_handleLocalClip(item));
  }

  Future<void> _handleLocalClip(ClipItem item) async {
    lastClip = item;
    try {
      await _historyStore?.add(item);
    } catch (error) {
      debugPrint('history write failed: $error');
    }
    if (settings!.autoSync && !_syncPaused) {
      await _broadcast(item);
    }
    _safeNotify();
  }

  Future<int> _broadcast(ClipItem item) async {
    var sent = 0;
    for (final connection in _connections.values.toList()) {
      if (connection.isClosed) continue;
      try {
        await connection.sendClip(item);
        sent++;
      } catch (error) {
        debugPrint('send clip failed: $error');
      }
    }
    if (sent > 0) lastSyncAt = DateTime.now();
    return sent;
  }

  Future<void> _handleRemoteClip(String fromName, ClipItem item) async {
    if (settings == null || _syncPaused || !settings!.autoSync) return;
    if (item.kind == ClipKind.text && !settings!.syncText) return;
    if (item.kind == ClipKind.image && !settings!.syncImages) return;
    final now = DateTime.now();
    _seenIncoming.removeWhere(
      (_, seenAt) => now.difference(seenAt) > const Duration(minutes: 2),
    );
    if (_seenIncoming.containsKey(item.id)) return;
    _seenIncoming[item.id] = now;
    try {
      await _historyStore?.add(item);
    } catch (error) {
      debugPrint('history write failed: $error');
    }
    final applied = await _clipboard?.applyRemote(item) ?? false;
    lastClip = item;
    lastSyncAt = now;
    _safeNotify();
    _notice(
      applied
          ? '已同步 $fromName 的${item.kind == ClipKind.text ? '文字' : '图片'}'
          : '已收到 $fromName 的内容，但写入剪贴板失败',
    );
  }

  /// Explicit "sync now" action. It also works when automatic syncing is off.
  Future<void> syncClipboardNow() async {
    final clipboard = _clipboard;
    if (clipboard == null) {
      _notice('剪贴板服务尚未就绪');
      return;
    }
    try {
      final item = await clipboard.captureCurrent();
      if (item == null) {
        _notice('剪贴板中没有可同步的文字或图片');
        return;
      }
      await _historyStore?.add(item);
      lastClip = item;
      final count = await _broadcast(item);
      _safeNotify();
      _notice(count == 0 ? '已记录到剪贴板历史，当前没有已连接设备' : '已发送到 $count 台设备');
    } catch (error) {
      _notice('读取剪贴板失败：$error');
    }
  }

  Future<void> copyHistoryItem(ClipItem item) async {
    final clipboard = _clipboard;
    if (clipboard == null) return;
    final ok = await clipboard.applyRemote(item);
    if (ok) _notice('已复制到本机剪贴板');
  }

  Future<void> sendHistoryItem(ClipItem item) async {
    final count = await _broadcast(item);
    if (count == 0) {
      _notice('当前没有已连接设备，请先配对');
    } else {
      _notice('已发送到 $count 台设备');
    }
  }

  Future<void> clearHistory() async {
    await _historyStore?.clear();
    _safeNotify();
    _notice('剪贴板历史已清空');
  }

  Future<void> removeHistoryItem(ClipItem item) async {
    await _historyStore?.remove(item.id);
    _safeNotify();
  }

  Future<bool> _approveIncomingPair(IncomingPairingRequest request) async {
    if (_outgoingPairing != null) {
      _notice('正在与另一台设备配对，请稍后再试');
      return false;
    }
    if (_incomingDecision != null) {
      _notice('已有待确认的配对请求');
      return false;
    }
    _incomingPairing = IncomingPairingState(
      peerId: request.peerId,
      name: cleanDeviceName(request.name),
      platform: request.platform,
      sas: request.sas,
    );
    final completer = Completer<bool>();
    _incomingDecision = completer;
    _incomingPairingTimer?.cancel();
    _incomingPairingTimer = Timer(const Duration(seconds: 60), () {
      if (completer.isCompleted) return;
      completer.complete(false);
      _incomingPairing = null;
      _incomingDecision = null;
      _incomingPairingTimer = null;
      _safeNotify();
      _notice('配对请求已超时');
    });
    _safeNotify();
    return completer.future;
  }

  void acceptIncomingPairing() {
    final completer = _incomingDecision;
    if (completer == null || _incomingPairing == null) return;
    _incomingDecision = null;
    _incomingPairing = null;
    _incomingPairingTimer?.cancel();
    _incomingPairingTimer = null;
    if (!completer.isCompleted) completer.complete(true);
    _safeNotify();
  }

  void declineIncomingPairing() {
    final completer = _incomingDecision;
    if (completer == null) return;
    _incomingDecision = null;
    _incomingPairing = null;
    _incomingPairingTimer?.cancel();
    _incomingPairingTimer = null;
    if (!completer.isCompleted) completer.complete(false);
    _safeNotify();
  }

  Future<void> pairWithDevice(PeerPresence presence) async {
    if (_outgoingPairing != null) {
      _notice('请先完成当前配对');
      return;
    }
    if (_peers.containsKey(presence.id)) {
      await connectPaired(presence.id, manual: true);
      return;
    }
    final state = OutgoingPairingState(
      peerId: presence.id,
      name: presence.name,
      platform: presence.platform,
      isCodeMode: false,
    );
    _outgoingPairing = state;
    _safeNotify();
    await _runPairing(
      state: state,
      addresses: presence.addresses,
      port: presence.port,
      mode: ConnectionMode.pair,
    );
  }

  Future<void> pairWithCode({
    required String endpoint,
    required String code,
  }) async {
    if (_outgoingPairing != null) {
      _notice('请先完成当前配对');
      return;
    }
    final normalized = normalizePairingCode(code);
    if (normalized.length != 8) {
      _notice('配对码应为 8 位字母或数字');
      return;
    }
    final parsed = parseEndpoint(endpoint);
    if (parsed == null) {
      _notice('请输入正确的设备地址，例如 192.168.1.8:47820');
      return;
    }
    final state = OutgoingPairingState(
      peerId: '',
      name: '配对码连接',
      platform: 'unknown',
      isCodeMode: true,
    );
    _outgoingPairing = state;
    _safeNotify();
    await _runPairing(
      state: state,
      addresses: <String>[parsed.host],
      port: parsed.port,
      mode: ConnectionMode.code,
      code: normalized,
    );
  }

  Future<void> _runPairing({
    required OutgoingPairingState state,
    required List<String> addresses,
    required int port,
    required ConnectionMode mode,
    String? code,
  }) async {
    Object? lastError;
    for (final address in addresses) {
      if (state.finished || state.cancellation.isCancelled) break;
      try {
        final connection = await PeerConnection.connect(
          host: address,
          port: port,
          identity: identity!,
          mode: mode,
          knownPeer: null,
          expectedPeerId: mode == ConnectionMode.pair ? state.peerId : null,
          pairingCode: code,
          cancellation: state.cancellation,
          onSas: (sas) {
            if (_outgoingPairing != state) return;
            state.sas = sas;
            _safeNotify();
          },
          onPeerPaired: _savePeer,
          onClip: (item) async {
            await _handleRemoteClip(item.originName, item);
          },
          onClosed: _handleConnectionClosed,
        );
        if (state.cancellation.isCancelled) {
          await connection.close(reason: '配对已取消');
          return;
        }
        state.finished = true;
        _outgoingPairing = null;
        _registerConnection(connection);
        _notice('已与 ${connection.name} 配对，剪贴板可以互传了');
        return;
      } on PairingCancelledException {
        return;
      } catch (error) {
        lastError = error;
        if (state.sas != null) break;
      }
    }
    if (state.cancellation.isCancelled) return;
    state.finished = true;
    state.error = _friendlyError(lastError);
    _safeNotify();
  }

  void dismissOutgoingPairing() {
    final state = _outgoingPairing;
    if (state == null) return;
    if (!state.finished) state.cancellation.cancel();
    _outgoingPairing = null;
    _safeNotify();
  }

  Future<void> reconnectPaired(String peerId) async {
    await connectPaired(peerId, manual: true);
  }

  Future<void> connectPaired(String peerId, {bool manual = false}) async {
    if (_stopping || _servicesStarted == false) return;
    final peer = _peers[peerId];
    if (peer == null) return;
    if (_connections.containsKey(peerId) && !_connections[peerId]!.isClosed) {
      if (manual) _notice('${peer.name} 已连接');
      return;
    }
    if (_connecting.contains(peerId)) {
      if (manual) _notice('正在连接 ${peer.name}…');
      return;
    }
    final presence = _presence[peerId];
    final port = presence?.port ?? peer.lastPort;
    final addresses = <String>{
      ...?presence?.addresses,
      if (peer.lastAddress != null) peer.lastAddress!,
    }.toList();
    if (port == null || addresses.isEmpty) {
      if (manual) _notice('${peer.name} 不在线，请让两台设备连接同一 Wi-Fi');
      return;
    }
    _connecting.add(peerId);
    _safeNotify();
    Object? lastError;
    try {
      for (final address in addresses) {
        if (_stopping) return;
        try {
          final connection = await PeerConnection.connect(
            host: address,
            port: port,
            identity: identity!,
            mode: ConnectionMode.connect,
            knownPeer: peer,
            expectedPeerId: peer.id,
            onPeerPaired: _savePeer,
            onClip: (item) async {
              await _handleRemoteClip(item.originName, item);
            },
            onClosed: _handleConnectionClosed,
          );
          _registerConnection(connection);
          return;
        } catch (error) {
          lastError = error;
        }
      }
      if (manual) {
        _notice('连接 ${peer.name} 失败：${_friendlyError(lastError)}');
      }
    } finally {
      _connecting.remove(peerId);
      _safeNotify();
    }
  }

  void _autoConnectTick() {
    if (!_servicesStarted ||
        _stopping ||
        !_foreground ||
        settings == null ||
        !settings!.autoConnect) {
      return;
    }
    for (final peer in _peers.values) {
      if (_connections.containsKey(peer.id) ||
          _connecting.contains(peer.id) ||
          _presence[peer.id] == null) {
        continue;
      }
      // Deterministic initiator avoids two simultaneous TCP connections.
      if (identity!.id.compareTo(peer.id) >= 0) continue;
      unawaited(connectPaired(peer.id));
    }
  }

  void _registerConnection(PeerConnection connection) {
    if (_disposed || _stopping) {
      unawaited(connection.close(reason: '应用正在关闭'));
      return;
    }
    final existing = _connections[connection.peerId];
    if (existing != null && !existing.isClosed && existing != connection) {
      unawaited(connection.close(reason: '重复连接'));
      return;
    }
    if (existing != null && existing != connection) {
      unawaited(existing.close(reason: '连接已被新会话替换'));
    }
    _connections[connection.peerId] = connection;
    _connecting.remove(connection.peerId);
    _peers[connection.peerId] = connection.peer;
    unawaited(_persistPeers());
    lastSyncAt = DateTime.now();
    _safeNotify();
    _notice('已连接到 ${connection.name}');
  }

  void _handleConnectionClosed(PeerConnection connection, String reason) {
    final current = _connections[connection.peerId];
    if (current != connection) return;
    _connections.remove(connection.peerId);
    _safeNotify();
    if (!_stopping && _foreground && reason != '主动断开连接') {
      _notice('${connection.name} 已断开');
    }
  }

  Future<void> _savePeer(PairedPeer peer, bool isNew) async {
    _peers[peer.id] = peer;
    _safeNotify();
    await _persistPeers();
    if (isNew) {
      _notice('已与 ${peer.name} 完成端到端加密配对');
    }
  }

  Future<void> _persistPeers() async {
    try {
      await _peerStore.save(Map<String, PairedPeer>.from(_peers));
    } catch (error) {
      debugPrint('persist peers failed: $error');
    }
  }

  Future<void> unpair(String peerId) async {
    final connection = _connections.remove(peerId);
    if (connection != null) await connection.close(reason: '已取消配对');
    _peers.remove(peerId);
    await _persistPeers();
    _safeNotify();
    _notice('已取消与 ${_presence[peerId]?.name ?? '该设备'} 的配对');
  }

  Future<void> createPairingCode() async {
    if (_serverPort == 0) {
      _notice('局域网服务尚未启动');
      return;
    }
    _pairingCodes.generate();
    _pairingCodeTimer?.cancel();
    _pairingCodeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_pairingCodes.active == null) {
        _pairingCodeTimer?.cancel();
        _pairingCodeTimer = null;
      }
      _safeNotify();
    });
    _safeNotify();
  }

  void clearPairingCode() {
    _pairingCodes.clear();
    _pairingCodeTimer?.cancel();
    _pairingCodeTimer = null;
    _safeNotify();
  }

  void _clearPairingCodeAfterUse() {
    _pairingCodes.consume();
    _pairingCodeTimer?.cancel();
    _pairingCodeTimer = null;
    _safeNotify();
    _notice('配对码已使用并失效');
  }

  void toggleSyncPause() {
    _syncPaused = !_syncPaused;
    _safeNotify();
    _notice(_syncPaused ? '同步已暂停' : '同步已恢复');
  }

  Future<void> setDeviceName(String name) async {
    final cleaned = cleanDeviceName(name);
    if (identity!.name == cleaned) return;
    identity!.name = cleaned;
    await _identityStore.save(identity!);
    await _discovery?.updateAdvertisement();
    _safeNotify();
  }

  Future<void> setDiscoverable(bool value) async {
    settings!.discoverable = value;
    await _settingsStore.save(settings!);
    if (value) {
      await _startDiscovery();
    } else {
      await _stopDiscovery();
    }
    _safeNotify();
  }

  Future<void> setAutoConnect(bool value) async {
    settings!.autoConnect = value;
    await _settingsStore.save(settings!);
    _safeNotify();
  }

  Future<void> setAutoSync(bool value) async {
    settings!.autoSync = value;
    await _settingsStore.save(settings!);
    _safeNotify();
  }

  Future<void> setSyncText(bool value) async {
    settings!.syncText = value;
    await _settingsStore.save(settings!);
    _safeNotify();
  }

  Future<void> setSyncImages(bool value) async {
    settings!.syncImages = value;
    await _settingsStore.save(settings!);
    _safeNotify();
  }

  Future<void> setAutoMonitor(bool value) async {
    settings!.autoMonitor = value;
    await _settingsStore.save(settings!);
    if (value && _foreground) {
      await _startClipboardMonitoring();
    } else if (!value) {
      await _stopClipboardMonitoring();
    }
    _safeNotify();
  }

  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (clipboardMonitoringIsForegroundOnly) {
      if (foreground && settings?.autoMonitor == true) {
        unawaited(_startClipboardMonitoring());
      } else if (!foreground) {
        unawaited(_stopClipboardMonitoring());
      }
    }
    if (foreground) {
      unawaited(_refreshNetwork());
      _autoConnectTick();
    }
    _safeNotify();
  }

  Future<void> _refreshNetwork() async {
    if (_discovery == null || _stopping) return;
    try {
      await _discovery!.updateAdvertisement();
      _localAddresses = _discovery!.localAddresses;
      if (_localAddresses.isNotEmpty) networkError = null;
      _safeNotify();
    } catch (_) {}
  }

  static ({String host, int port})? parseEndpoint(String input) {
    final value = input.trim();
    if (value.isEmpty) return null;
    final match = RegExp(r'^([0-9a-zA-Z\.\-]+)(?::(\d{1,5}))?$').firstMatch(value);
    if (match == null) return null;
    final host = match.group(1)!;
    if (InternetAddress.tryParse(host) == null) return null;
    final port = match.group(2) == null ? defaultPeerPort : int.tryParse(match.group(2)!);
    if (port == null || port < 1 || port > 65535) return null;
    return (host: host, port: port);
  }

  static String endpointToString(({String host, int port}) endpoint) =>
      '${endpoint.host}:${endpoint.port}';

  String _friendlyError(Object? error) {
    if (error == null) return '连接失败';
    if (error is PeerProtocolException) return error.message;
    if (error is TimeoutException) return '连接超时';
    if (error is SocketException) return '网络不可达';
    if (error is PairingCancelledException) return '已取消';
    return '$error';
  }

  void _notice(String message) {
    if (_disposed) return;
    if (!_notices.isClosed) _notices.add(message);
    debugPrint('[notice] $message');
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  /// Seeds in-memory state for deterministic widget previews and layout tests.
  @visibleForTesting
  void seedPreviewState({
    required LocalIdentity localIdentity,
    required AppSettings appSettings,
    Map<String, PairedPeer> peers = const <String, PairedPeer>{},
    Map<String, PeerPresence> presence = const <String, PeerPresence>{},
    List<ClipItem> history = const <ClipItem>[],
    ClipItem? latestClip,
    List<String> localAddresses = const <String>['192.168.1.8'],
    int serverPort = defaultPeerPort,
    bool syncPaused = false,
  }) {
    identity = localIdentity;
    settings = appSettings;
    _peers
      ..clear()
      ..addAll(peers);
    _presence
      ..clear()
      ..addAll(presence);
    _previewHistory = List<ClipItem>.of(history);
    lastClip = latestClip ?? (history.isEmpty ? null : history.first);
    _localAddresses = List<String>.of(localAddresses);
    _serverPort = serverPort;
    _syncPaused = syncPaused;
    _initialized = true;
    _loading = false;
    _safeNotify();
  }

  Future<void> shutdown() async {
    if (_stopping) return;
    _stopping = true;
    _autoConnectTimer?.cancel();
    _pairingCodeTimer?.cancel();
    _incomingPairingTimer?.cancel();
    _networkRefreshTimer?.cancel();
    _incomingDecision?.complete(false);
    _incomingDecision = null;
    for (final connection in _connections.values.toList()) {
      await connection.close(reason: '应用已停止');
    }
    _connections.clear();
    await _server?.stop();
    await _discovery?.stop();
    await _clipboard?.stop();
    _server = null;
    _discovery = null;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(shutdown());
    _notices.close();
    super.dispose();
  }
}
