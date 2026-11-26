import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' hide Hmac;

const int protocolVersion = 1;
const String protocolMagic = 'cliplink/1';
const int kMaxWireFrameBytes = 32 * 1024 * 1024;
const int kMaxClipBytes = 20 * 1024 * 1024;
const int kMaxTextBytes = 512 * 1024;
const int kMaxHandshakeBytes = 64 * 1024;

const String _crockfordAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// Pairing codes are eight Crockford Base32 characters (40 bits).
String generatePairingCode() {
  final random = Random.secure();
  final bytes = List<int>.generate(5, (_) => random.nextInt(256));
  var buffer = 0;
  var bits = 0;
  final output = StringBuffer();
  for (final byte in bytes) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      output.write(_crockfordAlphabet[(buffer >> (bits - 5)) & 31]);
      bits -= 5;
    }
    buffer &= (1 << bits) - 1;
  }
  return output.toString();
}

/// Accepts lowercase, spaces, dashes, and common OCR confusions.
String normalizePairingCode(String input) {
  final normalized = input
      .toUpperCase()
      .replaceAll(RegExp(r'[^0-9A-Z]'), '')
      .replaceAll('I', '1')
      .replaceAll('L', '1')
      .replaceAll('O', '0');
  if (normalized.isEmpty) return '';
  if (!normalized.split('').every(_crockfordAlphabet.contains)) return '';
  return normalized;
}

String formatPairingCode(String code) {
  final normalized = normalizePairingCode(code);
  if (normalized.length <= 4) return normalized;
  return '${normalized.substring(0, 4)}-${normalized.substring(4)}';
}

Uint8List _field(Object value) {
  final bytes = value is Uint8List ? value : utf8.encode(value.toString());
  final length = ByteData(4)..setUint32(0, bytes.length);
  final builder = BytesBuilder(copy: false)
    ..add(length.buffer.asUint8List())
    ..add(bytes);
  return builder.takeBytes();
}

Uint8List _joinFields(List<Object> fields) {
  final builder = BytesBuilder(copy: false);
  for (final field in fields) {
    builder.add(_field(field));
  }
  return builder.takeBytes();
}

Uint8List hmacSha256(List<int> key, List<int> data) {
  return Uint8List.fromList(Hmac(sha256, key).convert(data).bytes);
}

Uint8List sha256Bytes(List<int> data) {
  return Uint8List.fromList(sha256.convert(data).bytes);
}

bool constantTimeEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}

Uint8List hkdfExtractExpand({
  required List<int> inputKeyMaterial,
  required List<int> salt,
  required String info,
  required int length,
}) {
  final prk = hmacSha256(salt, inputKeyMaterial);
  final infoBytes = utf8.encode(info);
  final output = BytesBuilder(copy: false);
  var previous = Uint8List(0);
  var counter = 1;
  while (output.length < length) {
    previous = hmacSha256(prk, <int>[...previous, ...infoBytes, counter]);
    output.add(previous);
    counter++;
    if (counter > 255) throw StateError('HKDF output too large');
  }
  return Uint8List.sublistView(output.takeBytes(), 0, length);
}

/// The canonical, authenticated description of a handshake. Both sides must
/// build this from identical values.
Uint8List buildTranscript({
  required String mode,
  required String clientId,
  required String serverId,
  required String clientName,
  required String serverName,
  required Uint8List clientNonce,
  required Uint8List serverNonce,
  required Uint8List clientEphemeralPublic,
  required Uint8List serverEphemeralPublic,
}) {
  return _joinFields(<Object>[
    protocolMagic,
    protocolVersion,
    mode,
    clientId,
    serverId,
    clientName,
    serverName,
    clientNonce,
    serverNonce,
    clientEphemeralPublic,
    serverEphemeralPublic,
  ]);
}

String sasFromTranscriptHash(List<int> transcriptHash) {
  final digest = sha256Bytes(<int>[
    ...utf8.encode('cliplink-sas-v1'),
    ...transcriptHash,
  ]);
  final view = ByteData.sublistView(Uint8List.fromList(digest));
  final number = view.getUint32(0) % 1000000;
  return number.toString().padLeft(6, '0');
}

Uint8List pairingCodeProof({
  required String code,
  required String clientId,
  required Uint8List clientNonce,
  required Uint8List clientPublicKey,
}) {
  final normalized = normalizePairingCode(code);
  return hmacSha256(
    utf8.encode(normalized),
    _joinFields(<Object>[
      'cliplink/code-hello/v1',
      protocolVersion,
      clientId,
      clientNonce,
      clientPublicKey,
    ]),
  );
}

Uint8List pairingCodeServerProof({
  required String code,
  required String serverId,
  required Uint8List clientProof,
  required Uint8List serverNonce,
  required Uint8List serverPublicKey,
}) {
  final normalized = normalizePairingCode(code);
  return hmacSha256(
    utf8.encode(normalized),
    _joinFields(<Object>[
      'cliplink/code-ack/v1',
      protocolVersion,
      serverId,
      clientProof,
      serverNonce,
      serverPublicKey,
    ]),
  );
}

Uint8List authProof({
  required Uint8List secret,
  required String role,
  required Uint8List transcriptHash,
}) {
  return hmacSha256(
    secret,
    _joinFields(<Object>['cliplink/auth/v1', protocolVersion, role, transcriptHash]),
  );
}

class EphemeralKey {
  EphemeralKey(this.keyPair, this.publicKey);

  final SimpleKeyPair keyPair;
  final Uint8List publicKey;

  static Future<EphemeralKey> generate() async {
    final keyPair = await X25519().newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    return EphemeralKey(keyPair, Uint8List.fromList(publicKey.bytes));
  }
}

class HandshakeSession {
  HandshakeSession({
    required this.transcriptHash,
    required this.sas,
    required this.clientToServerKey,
    required this.serverToClientKey,
    required this.clientToServerIv,
    required this.serverToClientIv,
    required this.pairingSecret,
  });

  final Uint8List transcriptHash;
  final String sas;
  final Uint8List clientToServerKey;
  final Uint8List serverToClientKey;
  final Uint8List clientToServerIv;
  final Uint8List serverToClientIv;
  final Uint8List pairingSecret;

  static Future<HandshakeSession> derive({
    required SimpleKeyPair localEphemeral,
    required Uint8List remoteEphemeralPublic,
    required Uint8List transcript,
  }) async {
    final remote = SimplePublicKey(
      remoteEphemeralPublic,
      type: KeyPairType.x25519,
    );
    final sharedSecret = await X25519().sharedSecretKey(
      keyPair: localEphemeral,
      remotePublicKey: remote,
    );
    final sharedBytes = await sharedSecret.extractBytes();
    final transcriptHash = sha256Bytes(transcript);
    final material = hkdfExtractExpand(
      inputKeyMaterial: sharedBytes,
      salt: transcriptHash,
      info: 'cliplink/session/v1',
      length: 72,
    );
    final pairingSecret = hkdfExtractExpand(
      inputKeyMaterial: sharedBytes,
      salt: transcriptHash,
      info: 'cliplink/pairing/v1',
      length: 32,
    );
    return HandshakeSession(
      transcriptHash: transcriptHash,
      sas: sasFromTranscriptHash(transcriptHash),
      clientToServerKey: Uint8List.sublistView(material, 0, 32),
      serverToClientKey: Uint8List.sublistView(material, 32, 64),
      clientToServerIv: Uint8List.sublistView(material, 64, 68),
      serverToClientIv: Uint8List.sublistView(material, 68, 72),
      pairingSecret: pairingSecret,
    );
  }
}

/// AES-256-GCM channel with deterministic, per-direction nonces. The send
/// counter is serialized by the connection's outbound queue.
class SecureChannel {
  SecureChannel({
    required this.sendKey,
    required this.receiveKey,
    required this.sendIvPrefix,
    required this.receiveIvPrefix,
  });

  final Uint8List sendKey;
  final Uint8List receiveKey;
  final Uint8List sendIvPrefix;
  final Uint8List receiveIvPrefix;

  final AesGcm _cipher = AesGcm.with256bits();
  int _sendCounter = 0;
  int _receiveCounter = 0;

  static Uint8List _nonce(Uint8List prefix, int counter) {
    final nonce = Uint8List(12);
    nonce.setRange(0, 4, prefix);
    ByteData.sublistView(nonce).setUint64(4, counter);
    return nonce;
  }

  Future<Uint8List> encrypt(List<int> plaintext) async {
    if (_sendCounter >= 0x7FFFFFFFFFFFFFFF) {
      throw StateError('Secure channel exhausted');
    }
    final secretBox = await _cipher.encrypt(
      plaintext,
      secretKey: SecretKey(sendKey),
      nonce: _nonce(sendIvPrefix, _sendCounter),
      aad: utf8.encode('cliplink/frame/v1'),
    );
    _sendCounter++;
    final output = BytesBuilder(copy: false)
      ..add(secretBox.cipherText)
      ..add(secretBox.mac.bytes);
    return output.takeBytes();
  }

  Future<Uint8List> decrypt(List<int> ciphertextAndTag) async {
    if (ciphertextAndTag.length < 16) {
      throw const FormatException('Encrypted frame is too short');
    }
    if (_receiveCounter >= 0x7FFFFFFFFFFFFFFF) {
      throw StateError('Secure channel exhausted');
    }
    final split = ciphertextAndTag.length - 16;
    final cipherText = Uint8List.fromList(
      ciphertextAndTag.sublist(0, split),
    );
    final tag = Uint8List.fromList(ciphertextAndTag.sublist(split));
    final plaintext = await _cipher.decrypt(
      SecretBox(
        cipherText,
        nonce: _nonce(receiveIvPrefix, _receiveCounter),
        mac: Mac(tag),
      ),
      secretKey: SecretKey(receiveKey),
      aad: utf8.encode('cliplink/frame/v1'),
    );
    _receiveCounter++;
    return Uint8List.fromList(plaintext);
  }
}

Map<String, Object?> decodeJsonMap(Uint8List bytes) {
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map) throw const FormatException('Expected JSON object');
  return decoded.cast<String, Object?>();
}

Map<String, Object?>? tryDecodeJsonMap(Uint8List bytes) {
  try {
    return decodeJsonMap(bytes);
  } catch (_) {
    return null;
  }
}

Uint8List encodeJsonMap(Map<String, Object?> value) {
  return Uint8List.fromList(utf8.encode(jsonEncode(value)));
}
