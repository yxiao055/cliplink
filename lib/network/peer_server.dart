import 'dart:async';
import 'dart:io';

import '../core/models.dart';
import 'pairing_code.dart';
import 'peer_connection.dart';

class PeerServer {
  PeerServer({
    required this.identity,
    required this.findPaired,
    required this.approvePairing,
    required this.onPeerPaired,
    required this.onClip,
    required this.onAuthenticated,
    required this.onConnectionClosed,
    required this.pairingCodes,
    this.onPairingCodeConsumed,
    this.onLog,
    this.preferredPort = 47820,
    this.portAttempts = 20,
  });

  final LocalIdentity identity;
  final PairedPeer? Function(String peerId) findPaired;
  final Future<bool> Function(IncomingPairingRequest request) approvePairing;
  final Future<void> Function(PairedPeer peer, bool isNew) onPeerPaired;
  final Future<void> Function(ClipItem item) onClip;
  final void Function(PeerConnection connection) onAuthenticated;
  final void Function(PeerConnection connection, String reason) onConnectionClosed;
  final PairingCodeStore pairingCodes;
  final void Function()? onPairingCodeConsumed;
  final void Function(String message)? onLog;
  final int preferredPort;
  final int portAttempts;

  ServerSocket? _server;
  final Set<PeerConnection> _connections = <PeerConnection>{};
  bool _stopping = false;

  int get port => _server?.port ?? 0;
  List<PeerConnection> get connections => List<PeerConnection>.unmodifiable(_connections);

  Future<void> start() async {
    if (_server != null) return;
    ServerSocket? server;
    Object? lastError;
    for (var offset = 0; offset < portAttempts; offset++) {
      try {
        server = await ServerSocket.bind(
          InternetAddress.anyIPv4,
          preferredPort + offset,
          shared: false,
        );
        break;
      } on SocketException catch (error) {
        lastError = error;
      }
    }
    if (server == null) {
      try {
        server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      } catch (error) {
        throw StateError('无法启动局域网服务：${lastError ?? error}');
      }
    }
    _server = server;
    server.listen(
      _handleSocket,
      onError: (Object error) {
        if (!_stopping) onLog?.call('局域网服务异常：$error');
      },
    );
    onLog?.call('局域网服务已启动，端口 ${server.port}');
  }

  void _handleSocket(Socket socket) {
    if (_stopping) {
      socket.destroy();
      return;
    }
    unawaited(_handshake(socket));
  }

  Future<void> _handshake(Socket socket) async {
    try {
      final connection = await PeerConnection.accept(
        socket: socket,
        identity: identity,
        findPaired: findPaired,
        pairingCodes: pairingCodes,
        approvePairing: approvePairing,
        onPeerPaired: onPeerPaired,
        onClip: onClip,
        onClosed: _handleClosed,
        onPairingCodeConsumed: onPairingCodeConsumed,
      );
      if (_stopping) {
        await connection.close(reason: '服务已停止');
        return;
      }
      _connections.add(connection);
      onAuthenticated(connection);
    } catch (error) {
      if (!_stopping) {
        onLog?.call('传入连接未完成：$error');
      }
      try {
        socket.destroy();
      } catch (_) {}
    }
  }

  void _handleClosed(PeerConnection connection, String reason) {
    if (_connections.remove(connection)) {
      onConnectionClosed(connection, reason);
    }
  }

  Future<void> stop() async {
    if (_stopping) return;
    _stopping = true;
    await _server?.close();
    _server = null;
    final active = _connections.toList();
    _connections.clear();
    for (final connection in active) {
      await connection.close(reason: '应用已停止');
    }
  }
}
