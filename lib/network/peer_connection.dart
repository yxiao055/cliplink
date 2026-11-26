// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/crypto.dart';
import '../core/local_store.dart';
import '../core/models.dart';
import 'pairing_code.dart';
import 'peer_link.dart';

enum ConnectionMode {
  pair,
  code,
  connect;

  String get wireName => name;
}

class PeerProtocolException implements Exception {
  PeerProtocolException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class PairingCancelledException implements Exception {
  @override
  String toString() => '已取消配对';
}

/// Allows the UI to abort an in-flight connection attempt.
class PairingCancellation {
  bool _cancelled = false;
  void Function()? _onCancel;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _onCancel?.call();
  }

  void _attach(void Function() callback) {
    _onCancel = callback;
    if (_cancelled) callback();
  }

  void _throwIfCancelled() {
    if (_cancelled) throw PairingCancelledException();
  }
}

class IncomingPairingRequest {
  IncomingPairingRequest({
    required this.peerId,
    required this.name,
    required this.platform,
    required this.sas,
  });

  final String peerId;
  final String name;
  final String platform;
  final String sas;
}

class _WirePeer {
  _WirePeer(this.id, this.name, this.platform);

  final String id;
  final String name;
  final String platform;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'platform': platform,
  };

  static _WirePeer parse(Object? value) {
    if (value is! Map) throw PeerProtocolException('bad-peer', '设备信息无效');
    final map = value.cast<String, Object?>();
    final id = map['id'];
    final name = map['name'];
    final platform = map['platform'];
    if (id is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(id) ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 64 ||
        platform is! String ||
        platform.length > 24) {
      throw PeerProtocolException('bad-peer', '设备信息无效');
    }
    return _WirePeer(id, name, platform);
  }
}

class PeerConnection {
  PeerConnection._({
    required this.peer,
    required this.localId,
    required this.initiator,
    required PeerLink link,
    required SecureChannel channel,
    required Future<void> Function(ClipItem item) onClip,
    required void Function(PeerConnection connection, String reason) onClosed,
  }) : _link = link,
       _channel = channel,
       _onClip = onClip,
       _onClosed = onClosed {
    _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_closed) return;
      sendControl(<String, Object?>{'t': 'ping'}).catchError((_) {});
    });
    unawaited(_receiveLoop());
  }

  final PairedPeer peer;
  final String localId;
  final bool initiator;
  final PeerLink _link;
  final SecureChannel _channel;
  final Future<void> Function(ClipItem item) _onClip;
  final void Function(PeerConnection connection, String reason) _onClosed;
  late final Timer _heartbeat;
  bool _closed = false;
  Future<void> _sendTail = Future<void>.value();
  DateTime lastActivity = DateTime.now();

  String get peerId => peer.id;
  String get name => peer.name;
  String get platform => peer.platform;
  String get remoteAddress => _link.remoteAddress;
  bool get isClosed => _closed;

  static Future<PeerConnection> connect({
    required String host,
    required int port,
    required LocalIdentity identity,
    required ConnectionMode mode,
    required Future<void> Function(ClipItem item) onClip,
    required void Function(PeerConnection connection, String reason) onClosed,
    PairedPeer? knownPeer,
    String? pairingCode,
    String? expectedPeerId,
    void Function(String sas)? onSas,
    Future<void> Function(PairedPeer peer, bool isNew)? onPeerPaired,
    PairingCancellation? cancellation,
    Duration connectTimeout = const Duration(seconds: 5),
    Duration handshakeTimeout = const Duration(seconds: 15),
    Duration approvalTimeout = const Duration(minutes: 2),
  }) async {
    if (mode == ConnectionMode.connect && knownPeer == null) {
      throw ArgumentError('knownPeer is required for reconnect');
    }
    if (mode == ConnectionMode.code &&
        (pairingCode == null || normalizePairingCode(pairingCode).length != 8)) {
      throw ArgumentError('A valid pairing code is required');
    }
    cancellation?._throwIfCancelled();
    final Socket socket;
    try {
      socket = await Socket.connect(host, port, timeout: connectTimeout);
    } catch (error) {
      throw PeerProtocolException('connect-failed', '无法连接到设备：$error');
    }
    final link = PeerLink(socket);
    cancellation?._attach(link.close);
    try {
      final ephemeral = await EphemeralKey.generate();
      final clientNonce = randomBytes(16);
      final normalizedCode = pairingCode == null
          ? null
          : normalizePairingCode(pairingCode);
      Uint8List? clientCodeProof;
      if (mode == ConnectionMode.code) {
        clientCodeProof = pairingCodeProof(
          code: normalizedCode!,
          clientId: identity.id,
          clientNonce: clientNonce,
          clientPublicKey: ephemeral.publicKey,
        );
      }
      final clientName = cleanDeviceName(identity.name);
      final hello = <String, Object?>{
        't': 'hello',
        'v': protocolVersion,
        'mode': mode.wireName,
        'client': <String, Object?>{
          'id': identity.id,
          'name': clientName,
          'platform': identity.platform,
        },
        'nonce': base64Encode(clientNonce),
        'pub': base64Encode(ephemeral.publicKey),
        if (clientCodeProof != null) 'codeProof': base64Encode(clientCodeProof),
        'serverId': ?expectedPeerId,
      };
      await _sendPlain(link, hello);
      cancellation?._throwIfCancelled();
      final ack = await _readMessage(link, handshakeTimeout);
      if (ack['t'] != 'helloAck' || ack['v'] != protocolVersion) {
        throw PeerProtocolException('bad-ack', '对方的握手响应无效');
      }
      final ackServer = _WirePeer.parse(ack['server']);
      if (ackServer.id == identity.id) {
        throw PeerProtocolException('self', '不能与本机配对');
      }
      if (expectedPeerId != null && ackServer.id != expectedPeerId) {
        throw PeerProtocolException('identity-mismatch', '设备身份与预期不一致');
      }
      if (mode == ConnectionMode.connect && ackServer.id != knownPeer!.id) {
        throw PeerProtocolException('identity-mismatch', '设备身份与已配对记录不一致');
      }
      final serverNonce = _decodeBase64Field(ack['nonce'], 16, 'nonce');
      final serverPublicKey = _decodeBase64Field(ack['pub'], 32, 'pub');
      final serverName = ackServer.name;
      final transcript = buildTranscript(
        mode: mode.wireName,
        clientId: identity.id,
        serverId: ackServer.id,
        clientName: clientName,
        serverName: serverName,
        clientNonce: clientNonce,
        serverNonce: serverNonce,
        clientEphemeralPublic: ephemeral.publicKey,
        serverEphemeralPublic: serverPublicKey,
      );
      final keys = await HandshakeSession.derive(
        localEphemeral: ephemeral.keyPair,
        remoteEphemeralPublic: serverPublicKey,
        transcript: transcript,
      );
      if (mode == ConnectionMode.code) {
        final serverProof = _decodeBase64Field(
          ack['codeProof'],
          32,
          'codeProof',
        );
        final expected = pairingCodeServerProof(
          code: normalizedCode!,
          serverId: ackServer.id,
          clientProof: clientCodeProof!,
          serverNonce: serverNonce,
          serverPublicKey: serverPublicKey,
        );
        if (!constantTimeEqual(serverProof, expected)) {
          throw PeerProtocolException('code-proof', '配对码校验失败，请重新生成配对码');
        }
      }
      cancellation?._throwIfCancelled();
      if (mode == ConnectionMode.pair) {
        onSas?.call(keys.sas);
        final approval = await _readMessage(link, approvalTimeout);
        if (approval['t'] != 'pairAccept') {
          throw PeerProtocolException('pair-failed', '对方未接受配对请求');
        }
      }
      cancellation?._throwIfCancelled();
      final authSecret = mode == ConnectionMode.connect
          ? knownPeer!.secret
          : keys.pairingSecret;
      final clientProof = authProof(
        secret: authSecret,
        role: 'client',
        transcriptHash: keys.transcriptHash,
      );
      await _sendPlain(link, <String, Object?>{
        't': 'auth',
        'proof': base64Encode(clientProof),
      });
      final ok = await _readMessage(link, handshakeTimeout);
      if (ok['t'] != 'authOk') {
        throw PeerProtocolException('bad-auth', '对方的认证响应无效');
      }
      final serverProof = _decodeBase64Field(ok['proof'], 32, 'proof');
      final expectedServerProof = authProof(
        secret: authSecret,
        role: 'server',
        transcriptHash: keys.transcriptHash,
      );
      if (!constantTimeEqual(serverProof, expectedServerProof)) {
        throw PeerProtocolException('auth-failed', '设备认证失败，配对记录可能已失效');
      }
      cancellation?._throwIfCancelled();
      final isNew = mode != ConnectionMode.connect;
      final now = DateTime.now();
      final peer = isNew
          ? PairedPeer(
              id: ackServer.id,
              name: ackServer.name,
              platform: ackServer.platform,
              secret: keys.pairingSecret,
              pairedAt: now,
              lastAddress: host,
              lastPort: port,
              lastConnectedAt: now,
            )
          : knownPeer!.copyWith(
              name: ackServer.name,
              platform: ackServer.platform,
              lastAddress: host,
              lastPort: port,
              lastConnectedAt: now,
            );
      if (onPeerPaired != null) {
        await onPeerPaired(peer, isNew);
      }
      final secureChannel = SecureChannel(
        sendKey: keys.clientToServerKey,
        receiveKey: keys.serverToClientKey,
        sendIvPrefix: keys.clientToServerIv,
        receiveIvPrefix: keys.serverToClientIv,
      );
      return PeerConnection._(
        peer: peer,
        localId: identity.id,
        initiator: true,
        link: link,
        channel: secureChannel,
        onClip: onClip,
        onClosed: onClosed,
      );
    } catch (error) {
      await link.close();
      if (cancellation?.isCancelled ?? false) {
        throw PairingCancelledException();
      }
      rethrow;
    }
  }

  static Future<PeerConnection> accept({
    required Socket socket,
    required LocalIdentity identity,
    required PairedPeer? Function(String peerId) findPaired,
    required PairingCodeStore pairingCodes,
    required Future<bool> Function(IncomingPairingRequest request) approvePairing,
    required Future<void> Function(PairedPeer peer, bool isNew) onPeerPaired,
    required Future<void> Function(ClipItem item) onClip,
    required void Function(PeerConnection connection, String reason) onClosed,
    void Function()? onPairingCodeConsumed,
    Duration handshakeTimeout = const Duration(seconds: 15),
    Duration approvalTimeout = const Duration(minutes: 2),
  }) async {
    final link = PeerLink(socket);
    try {
      final hello = await _readMessage(link, handshakeTimeout);
      if (hello['t'] != 'hello' || hello['v'] != protocolVersion) {
        throw PeerProtocolException('bad-message', '握手消息无效');
      }
      final mode = ConnectionMode.values.firstWhere(
        (value) => value.wireName == hello['mode'],
        orElse: () => throw PeerProtocolException('bad-mode', '不支持的连接方式'),
      );
      final client = _WirePeer.parse(hello['client']);
      if (client.id == identity.id) {
        throw PeerProtocolException('self', '不能与本机配对');
      }
      final requestedServer = hello['serverId'];
      if (requestedServer is String && requestedServer != identity.id) {
        throw PeerProtocolException('wrong-device', '连接到了错误的设备');
      }
      final clientNonce = _decodeBase64Field(hello['nonce'], 16, 'nonce');
      final clientPublicKey = _decodeBase64Field(hello['pub'], 32, 'pub');
      Uint8List? clientCodeProof;
      PairingCodeEntry? codeEntry;
      if (mode == ConnectionMode.code) {
        codeEntry = pairingCodes.active;
        if (codeEntry == null) {
          throw PeerProtocolException('code-invalid', '配对码错误或已过期');
        }
        clientCodeProof = _decodeBase64Field(
          hello['codeProof'],
          32,
          'codeProof',
        );
        final expected = pairingCodeProof(
          code: codeEntry.normalized,
          clientId: client.id,
          clientNonce: clientNonce,
          clientPublicKey: clientPublicKey,
        );
        if (!constantTimeEqual(clientCodeProof, expected)) {
          throw PeerProtocolException('code-invalid', '配对码错误或已过期');
        }
      }

      PairedPeer? existing;
      if (mode == ConnectionMode.connect) {
        existing = findPaired(client.id);
        if (existing == null) {
          throw PeerProtocolException('not-paired', '此设备尚未与您配对');
        }
      }

      final ephemeral = await EphemeralKey.generate();
      final serverNonce = randomBytes(16);
      final serverName = cleanDeviceName(identity.name);
      final transcript = buildTranscript(
        mode: mode.wireName,
        clientId: client.id,
        serverId: identity.id,
        clientName: client.name,
        serverName: serverName,
        clientNonce: clientNonce,
        serverNonce: serverNonce,
        clientEphemeralPublic: clientPublicKey,
        serverEphemeralPublic: ephemeral.publicKey,
      );
      final keys = await HandshakeSession.derive(
        localEphemeral: ephemeral.keyPair,
        remoteEphemeralPublic: clientPublicKey,
        transcript: transcript,
      );
      final ack = <String, Object?>{
        't': 'helloAck',
        'v': protocolVersion,
        'mode': mode.wireName,
        'server': <String, Object?>{
          'id': identity.id,
          'name': serverName,
          'platform': identity.platform,
        },
        'nonce': base64Encode(serverNonce),
        'pub': base64Encode(ephemeral.publicKey),
      };
      if (mode == ConnectionMode.code) {
        ack['codeProof'] = base64Encode(
          pairingCodeServerProof(
            code: codeEntry!.normalized,
            serverId: identity.id,
            clientProof: clientCodeProof!,
            serverNonce: serverNonce,
            serverPublicKey: ephemeral.publicKey,
          ),
        );
      }
      await _sendPlain(link, ack);

      if (mode == ConnectionMode.pair) {
        final approved = await approvePairing(
          IncomingPairingRequest(
            peerId: client.id,
            name: client.name,
            platform: client.platform,
            sas: keys.sas,
          ),
        ).timeout(approvalTimeout, onTimeout: () => false);
        if (!approved) {
          await _sendPlain(link, <String, Object?>{
            't': 'error',
            'code': 'pair-declined',
            'message': '对方拒绝了配对请求',
          });
          throw PeerProtocolException('pair-declined', '配对请求被拒绝');
        }
        await _sendPlain(link, <String, Object?>{'t': 'pairAccept'});
      }

      final auth = await _readMessage(link, approvalTimeout);
      if (auth['t'] != 'auth') {
        throw PeerProtocolException('bad-auth', '认证消息无效');
      }
      final authSecret = mode == ConnectionMode.connect
          ? existing!.secret
          : keys.pairingSecret;
      final receivedProof = _decodeBase64Field(auth['proof'], 32, 'proof');
      final expectedProof = authProof(
        secret: authSecret,
        role: 'client',
        transcriptHash: keys.transcriptHash,
      );
      if (!constantTimeEqual(receivedProof, expectedProof)) {
        throw PeerProtocolException('auth-failed', '设备认证失败');
      }

      final now = DateTime.now();
      final isNew = mode != ConnectionMode.connect;
      final peer = isNew
          ? PairedPeer(
              id: client.id,
              name: client.name,
              platform: client.platform,
              secret: keys.pairingSecret,
              pairedAt: now,
              lastAddress: link.remoteAddress,
              lastPort: _linkRemotePort(link),
              lastConnectedAt: now,
            )
          : existing!.copyWith(
              name: client.name,
              platform: client.platform,
              lastAddress: link.remoteAddress,
              lastPort: _linkRemotePort(link),
              lastConnectedAt: now,
            );
      await onPeerPaired(peer, isNew);
      await _sendPlain(link, <String, Object?>{
        't': 'authOk',
        'proof': base64Encode(
          authProof(
            secret: authSecret,
            role: 'server',
            transcriptHash: keys.transcriptHash,
          ),
        ),
      });
      if (mode == ConnectionMode.code) {
        pairingCodes.consume();
        onPairingCodeConsumed?.call();
      }
      final channel = SecureChannel(
        sendKey: keys.serverToClientKey,
        receiveKey: keys.clientToServerKey,
        sendIvPrefix: keys.serverToClientIv,
        receiveIvPrefix: keys.clientToServerIv,
      );
      return PeerConnection._(
        peer: peer,
        localId: identity.id,
        initiator: false,
        link: link,
        channel: channel,
        onClip: onClip,
        onClosed: onClosed,
      );
    } catch (error) {
      try {
        if (!link.isClosed && error is PeerProtocolException) {
          await _sendPlain(link, <String, Object?>{
            't': 'error',
            'code': error.code,
            'message': error.message,
          }).timeout(const Duration(seconds: 2), onTimeout: () {});
        }
      } catch (_) {}
      await link.close();
      rethrow;
    }
  }

  Future<void> sendClip(ClipItem item) async {
    if (_closed) throw PeerLinkClosedException();
    if (item.kind == ClipKind.text) {
      if (item.byteSize > kMaxTextBytes) {
        throw PeerProtocolException('clip-too-large', '文本过长，未发送');
      }
    } else {
      if (item.byteSize > kMaxClipBytes) {
        throw PeerProtocolException('clip-too-large', '图片过大，未发送');
      }
      if (!looksLikePng(item.bytes!)) {
        throw PeerProtocolException('clip-invalid', '图片格式无效');
      }
    }
    final payload = item.kind == ClipKind.text
        ? Uint8List.fromList(utf8.encode(item.text!))
        : item.bytes!;
    await _sendSecure(
      messageType: 2,
      header: <String, Object?>{
        'id': item.id,
        'kind': item.kind.wireName,
        'ts': item.createdAt.millisecondsSinceEpoch,
        'originId': item.originId,
        'originName': item.originName,
        'sha256': item.hashHex,
        'size': payload.length,
      },
      payload: payload,
    );
  }

  Future<void> sendControl(Map<String, Object?> header) {
    if (_closed) return Future<void>.error(PeerLinkClosedException());
    return _sendSecure(messageType: 1, header: header, payload: Uint8List(0));
  }

  Future<void> _sendSecure({
    required int messageType,
    required Map<String, Object?> header,
    required Uint8List payload,
  }) async {
    final headerBytes = encodeJsonMap(header);
    final builder = BytesBuilder(copy: false)
      ..addByte(messageType)
      ..add((ByteData(4)..setUint32(0, headerBytes.length)).buffer.asUint8List())
      ..add(headerBytes)
      ..add(payload);
    final plaintext = builder.takeBytes();
    final completer = Completer<void>();
    _sendTail = _sendTail.then((_) async {
      if (_closed) throw PeerLinkClosedException();
      final cipherText = await _channel.encrypt(plaintext);
      await _link.sendFrame(secure: true, payload: cipherText);
    }).then(
      (_) => completer.complete(),
      onError: (Object error, StackTrace stackTrace) {
        completer.completeError(error, stackTrace);
      },
    );
    return completer.future;
  }

  Future<void> _receiveLoop() async {
    try {
      while (!_closed) {
        final frame = await _link.next(timeout: const Duration(seconds: 75));
        lastActivity = DateTime.now();
        if (!frame.secure) {
          throw PeerProtocolException('plain-after-auth', '收到未加密的数据');
        }
        final plaintext = await _channel.decrypt(frame.payload);
        await _handlePlaintext(plaintext);
      }
    } catch (error) {
      _finish(error is TimeoutException ? '连接超时' : '$error');
    }
  }

  Future<void> _handlePlaintext(Uint8List plaintext) async {
    if (plaintext.length < 5) {
      throw PeerProtocolException('bad-message', '消息格式无效');
    }
    final type = plaintext[0];
    final headerLength = ByteData.sublistView(plaintext, 1, 5).getUint32(0);
    if (headerLength > plaintext.length - 5) {
      throw PeerProtocolException('bad-message', '消息头部无效');
    }
    final headerBytes = Uint8List.sublistView(plaintext, 5, 5 + headerLength);
    final payload = Uint8List.sublistView(plaintext, 5 + headerLength);
    final header = decodeJsonMap(headerBytes);
    if (type == 1) {
      final kind = header['t'];
      if (kind == 'ping') {
        await sendControl(<String, Object?>{'t': 'pong'});
      } else if (kind == 'bye') {
        _finish('对方已断开连接');
      }
      return;
    }
    if (type != 2) {
      throw PeerProtocolException('bad-message', '未知的消息类型');
    }
    final item = _clipFromWire(header, payload);
    await _onClip(item);
  }

  ClipItem _clipFromWire(Map<String, Object?> header, Uint8List payload) {
    final kind = ClipKind.fromWire(header['kind'] as String?);
    final declaredSize = (header['size'] as num?)?.toInt();
    if (declaredSize == null || declaredSize != payload.length) {
      throw PeerProtocolException('bad-clip', '内容长度校验失败');
    }
    if (kind == ClipKind.text && payload.length > kMaxTextBytes) {
      throw PeerProtocolException('bad-clip', '文本内容过大');
    }
    if (kind == ClipKind.image) {
      if (payload.length > kMaxClipBytes || !looksLikePng(payload)) {
        throw PeerProtocolException('bad-clip', '图片内容无效');
      }
    }
    final now = DateTime.now();
    final remoteTs = (header['ts'] as num?)?.toInt();
    final createdAt = remoteTs == null
        ? now
        : DateTime.fromMillisecondsSinceEpoch(remoteTs);
    final safeCreatedAt = createdAt.difference(now).abs() > const Duration(days: 1)
        ? now
        : createdAt;
    final rawId = header['id'];
    final id = rawId is String && RegExp(r'^[0-9a-f]{32}$').hasMatch(rawId)
        ? rawId
        : newClipId();
    final originId = header['originId'] is String
        ? header['originId']! as String
        : peer.id;
    final originName = cleanDeviceName(
      header['originName'] is String ? header['originName']! as String : peer.name,
    );
    final ClipItem item;
    if (kind == ClipKind.text) {
      final text = utf8.decode(payload, allowMalformed: false);
      item = ClipItem(
        id: id,
        kind: ClipKind.text,
        text: text,
        createdAt: safeCreatedAt,
        originId: originId,
        originName: originName,
        incoming: true,
      );
    } else {
      item = ClipItem(
        id: id,
        kind: ClipKind.image,
        bytes: Uint8List.fromList(payload),
        createdAt: safeCreatedAt,
        originId: originId,
        originName: originName,
        incoming: true,
      );
    }
    final declaredHash = header['sha256'];
    if (declaredHash is! String ||
        declaredHash.toLowerCase() != item.hashHex) {
      throw PeerProtocolException('bad-clip', '内容完整性校验失败');
    }
    return item;
  }

  void _finish(String reason) {
    if (_closed) return;
    _closed = true;
    _heartbeat.cancel();
    unawaited(_link.close());
    _onClosed(this, reason);
  }

  Future<void> close({String reason = '主动断开连接'}) async {
    if (_closed) return;
    try {
      await sendControl(<String, Object?>{'t': 'bye'})
          .timeout(const Duration(milliseconds: 300), onTimeout: () {});
    } catch (_) {}
    _finish(reason);
  }
}

Future<void> _sendPlain(PeerLink link, Map<String, Object?> message) async {
  final payload = encodeJsonMap(message);
  if (payload.length > kMaxHandshakeBytes) {
    throw PeerProtocolException('handshake-too-large', '握手消息过大');
  }
  await link.sendFrame(secure: false, payload: payload);
}

Future<Map<String, Object?>> _readMessage(
  PeerLink link,
  Duration timeout,
) async {
  final frame = await link.next(timeout: timeout);
  if (frame.secure || frame.payload.length > kMaxHandshakeBytes) {
    throw PeerProtocolException('bad-handshake', '握手阶段收到了无效数据');
  }
  final message = decodeJsonMap(frame.payload);
  if (message['t'] == 'error') {
    throw PeerProtocolException(
      message['code'] as String? ?? 'remote-error',
      message['message'] as String? ?? '对方拒绝了连接',
    );
  }
  return message;
}

Uint8List _decodeBase64Field(Object? value, int length, String name) {
  if (value is! String) {
    throw PeerProtocolException('bad-field', '缺少 $name');
  }
  try {
    final bytes = base64Decode(value);
    if (bytes.length != length) throw const FormatException();
    return bytes;
  } catch (_) {
    throw PeerProtocolException('bad-field', '$name 格式无效');
  }
}

int _linkRemotePort(PeerLink link) => link.remotePort;
