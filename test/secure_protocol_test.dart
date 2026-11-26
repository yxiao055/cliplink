import 'dart:convert';
import 'dart:typed_data';

import 'package:cliplink/core/crypto.dart';
import 'package:cliplink/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pairing codes', () {
    test('generate eight unambiguous characters', () {
      for (var i = 0; i < 200; i++) {
        final code = generatePairingCode();
        expect(code.length, 8);
        expect(RegExp(r'^[0-9A-HJKMNP-TV-Z]{8}$').hasMatch(code), isTrue);
        expect(normalizePairingCode(code), code);
      }
    });

    test('normalize OCR confusions and formatting', () {
      expect(normalizePairingCode('abci-l0o8'), 'ABC11008');
      expect(normalizePairingCode('  abcd efgh  '), 'ABCDEFGH');
      expect(formatPairingCode('abcd-efgh'), 'ABCD-EFGH');
      expect(normalizePairingCode('invalid'), '1NVA11D');
      expect(normalizePairingCode('U'), '');
    });
  });

  group('cryptographic handshake', () {
    test('both sides derive the same SAS and session material', () async {
      final alice = await EphemeralKey.generate();
      final bob = await EphemeralKey.generate();
      final aliceNonce = randomBytes(16);
      final bobNonce = randomBytes(16);
      final transcript = buildTranscript(
        mode: 'pair',
        clientId: 'a' * 32,
        serverId: 'b' * 32,
        clientName: 'Alice Mac',
        serverName: 'Bob PC',
        clientNonce: aliceNonce,
        serverNonce: bobNonce,
        clientEphemeralPublic: alice.publicKey,
        serverEphemeralPublic: bob.publicKey,
      );
      final fromClient = await HandshakeSession.derive(
        localEphemeral: alice.keyPair,
        remoteEphemeralPublic: bob.publicKey,
        transcript: transcript,
      );
      final fromServer = await HandshakeSession.derive(
        localEphemeral: bob.keyPair,
        remoteEphemeralPublic: alice.publicKey,
        transcript: transcript,
      );

      expect(fromClient.sas, fromServer.sas);
      expect(fromClient.sas.length, 6);
      expect(fromClient.clientToServerKey, fromServer.clientToServerKey);
      expect(fromClient.serverToClientKey, fromServer.serverToClientKey);
      expect(fromClient.pairingSecret, fromServer.pairingSecret);
      expect(fromClient.transcriptHash, fromServer.transcriptHash);
    });

    test('a different transcript changes the SAS and keys', () async {
      final alice = await EphemeralKey.generate();
      final bob = await EphemeralKey.generate();
      final nonce = randomBytes(16);
      Uint8List transcript(String mode) => buildTranscript(
        mode: mode,
        clientId: 'a' * 32,
        serverId: 'b' * 32,
        clientName: 'Alice Mac',
        serverName: 'Bob PC',
        clientNonce: nonce,
        serverNonce: nonce,
        clientEphemeralPublic: alice.publicKey,
        serverEphemeralPublic: bob.publicKey,
      );
      final pair = await HandshakeSession.derive(
        localEphemeral: alice.keyPair,
        remoteEphemeralPublic: bob.publicKey,
        transcript: transcript('pair'),
      );
      final code = await HandshakeSession.derive(
        localEphemeral: alice.keyPair,
        remoteEphemeralPublic: bob.publicKey,
        transcript: transcript('code'),
      );
      expect(pair.sas, isNot(code.sas));
      expect(pair.pairingSecret, isNot(code.pairingSecret));
    });

    test('auth proofs are role and transcript specific', () async {
      final secret = randomBytes(32);
      final transcript = randomBytes(32);
      final client = authProof(
        secret: secret,
        role: 'client',
        transcriptHash: transcript,
      );
      final server = authProof(
        secret: secret,
        role: 'server',
        transcriptHash: transcript,
      );
      expect(client, isNot(server));
      expect(
        authProof(secret: secret, role: 'client', transcriptHash: transcript),
        client,
      );
      expect(
        constantTimeEqual(
          client,
          authProof(secret: secret, role: 'client', transcriptHash: randomBytes(32)),
        ),
        isFalse,
      );
    });

    test('pairing code proofs bind the code and handshake', () {
      final nonce = randomBytes(16);
      final pub = randomBytes(32);
      final proof = pairingCodeProof(
        code: 'ABCD-EFGH',
        clientId: 'a' * 32,
        clientNonce: nonce,
        clientPublicKey: pub,
      );
      final wrong = pairingCodeProof(
        code: 'ABCD-EFGJ',
        clientId: 'a' * 32,
        clientNonce: nonce,
        clientPublicKey: pub,
      );
      expect(proof, isNot(wrong));
      expect(proof.length, 32);
    });

    test('secure channel encrypts, authenticates and rejects tampering', () async {
      final alice = await EphemeralKey.generate();
      final bob = await EphemeralKey.generate();
      final transcript = buildTranscript(
        mode: 'code',
        clientId: 'a' * 32,
        serverId: 'b' * 32,
        clientName: 'Alice',
        serverName: 'Bob',
        clientNonce: randomBytes(16),
        serverNonce: randomBytes(16),
        clientEphemeralPublic: alice.publicKey,
        serverEphemeralPublic: bob.publicKey,
      );
      final clientKeys = await HandshakeSession.derive(
        localEphemeral: alice.keyPair,
        remoteEphemeralPublic: bob.publicKey,
        transcript: transcript,
      );
      final serverKeys = await HandshakeSession.derive(
        localEphemeral: bob.keyPair,
        remoteEphemeralPublic: alice.publicKey,
        transcript: transcript,
      );
      final client = SecureChannel(
        sendKey: clientKeys.clientToServerKey,
        receiveKey: clientKeys.serverToClientKey,
        sendIvPrefix: clientKeys.clientToServerIv,
        receiveIvPrefix: clientKeys.serverToClientIv,
      );
      final server = SecureChannel(
        sendKey: serverKeys.serverToClientKey,
        receiveKey: serverKeys.clientToServerKey,
        sendIvPrefix: serverKeys.serverToClientIv,
        receiveIvPrefix: serverKeys.clientToServerIv,
      );
      final plaintext = utf8.encode('hello, 剪链 📋');
      final encrypted = await client.encrypt(plaintext);
      expect(encrypted, isNot(plaintext));
      final decrypted = await server.decrypt(encrypted);
      expect(decrypted, plaintext);

      final tampered = Uint8List.fromList(encrypted);
      tampered[tampered.length - 1] ^= 1;
      await expectLater(server.decrypt(tampered), throwsA(anything));
    });
  });

  group('clip model', () {
    test('hash covers kind and payload', () {
      final text = ClipItem.textItem(
        text: 'abc',
        originId: 'a' * 32,
        originName: 'A',
      );
      final same = ClipItem.textItem(
        text: 'abc',
        originId: 'b' * 32,
        originName: 'B',
      );
      final different = ClipItem.textItem(
        text: 'abd',
        originId: 'a' * 32,
        originName: 'A',
      );
      expect(text.hashHex, same.hashHex);
      expect(text.hashHex, isNot(different.hashHex));
      expect(text.hashHex.length, 64);
    });
  });
}
