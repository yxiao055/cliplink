import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cliplink/core/models.dart';
import 'package:cliplink/network/pairing_code.dart';
import 'package:cliplink/network/peer_connection.dart';
import 'package:flutter_test/flutter_test.dart';

const _client = '11111111111111111111111111111111';
const _server = '22222222222222222222222222222222';

LocalIdentity _identity(String id, String name, String platform) {
  return LocalIdentity(id: id, name: name, platform: platform);
}

Uint8List _tinyPng() {
  return base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
}

void main() {
  test('pair confirmation, SAS matching and bidirectional encrypted clips', () async {
    final serverSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final serverApprovalSas = Completer<String>();
    final serverPaired = Completer<PairedPeer>();
    final serverClip = Completer<ClipItem>();
    final serverConnected = Completer<PeerConnection>();

    final serverTask = () async {
      final socket = await serverSocket.first.timeout(const Duration(seconds: 5));
      final connection = await PeerConnection.accept(
        socket: socket,
        identity: _identity(_server, 'Server PC', 'windows'),
        findPaired: (_) => null,
        pairingCodes: PairingCodeStore(),
        approvePairing: (request) async {
          if (!serverApprovalSas.isCompleted) {
            serverApprovalSas.complete(request.sas);
          }
          return true;
        },
        onPeerPaired: (peer, _) async {
          if (!serverPaired.isCompleted) serverPaired.complete(peer);
        },
        onClip: (item) async {
          if (!serverClip.isCompleted) serverClip.complete(item);
        },
        onClosed: (_, _) {},
      );
      serverConnected.complete(connection);
      return connection;
    }();

    final clientSas = Completer<String>();
    final clientPaired = Completer<PairedPeer>();
    final clientClip = Completer<ClipItem>();
    final clientConnection = await PeerConnection.connect(
      host: InternetAddress.loopbackIPv4.address,
      port: serverSocket.port,
      identity: _identity(_client, 'Client Mac', 'macos'),
      mode: ConnectionMode.pair,
      expectedPeerId: _server,
      onSas: (sas) {
        if (!clientSas.isCompleted) clientSas.complete(sas);
      },
      onPeerPaired: (peer, _) async {
        if (!clientPaired.isCompleted) clientPaired.complete(peer);
      },
      onClip: (item) async {
        if (!clientClip.isCompleted) clientClip.complete(item);
      },
      onClosed: (_, _) {},
    );
    final serverConnection = await serverConnected.future;
    addTearDown(() async {
      await clientConnection.close();
      await serverConnection.close();
      await serverSocket.close();
    });

    final clientCode = await clientSas.future.timeout(const Duration(seconds: 5));
    final serverCode = await serverApprovalSas.future.timeout(const Duration(seconds: 5));
    expect(clientCode, serverCode);
    expect(clientCode.length, 6);

    final fromClient = await clientPaired.future;
    final fromServer = await serverPaired.future;
    expect(fromClient.secret, fromServer.secret);
    expect(fromClient.id, _server);
    expect(fromServer.id, _client);
    expect(fromServer.name, 'Client Mac');

    final text = ClipItem.textItem(
      text: '跨屏幕的剪贴板 🚀\n第二行',
      originId: _client,
      originName: 'Client Mac',
    );
    await clientConnection.sendClip(text);
    final receivedText = await serverClip.future.timeout(const Duration(seconds: 5));
    expect(receivedText.kind, ClipKind.text);
    expect(receivedText.text, text.text);
    expect(receivedText.hashHex, text.hashHex);

    final image = ClipItem.imageItem(
      bytes: _tinyPng(),
      originId: _server,
      originName: 'Server PC',
    );
    await serverConnection.sendClip(image);
    final receivedImage = await clientClip.future.timeout(const Duration(seconds: 5));
    expect(receivedImage.kind, ClipKind.image);
    expect(receivedImage.bytes, image.bytes);
    expect(receivedImage.hashHex, image.hashHex);

    await clientConnection.close();
    await serverConnection.close();
    await serverSocket.close();
    await serverTask.catchError((Object _) => serverConnection);
  });

  test('pairing code exchange and authenticated reconnect', () async {
    final codes = PairingCodeStore();
    final code = codes.generate();
    final serverSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final serverPaired = Completer<PairedPeer>();
    final clientPaired = Completer<PairedPeer>();
    final serverConnected = Completer<PeerConnection>();

    final serverTask = () async {
      final socket = await serverSocket.first.timeout(const Duration(seconds: 5));
      final connection = await PeerConnection.accept(
        socket: socket,
        identity: _identity(_server, 'Server PC', 'windows'),
        findPaired: (_) => null,
        pairingCodes: codes,
        approvePairing: (_) async {
          fail('code pairing must not require manual approval');
        },
        onPeerPaired: (peer, _) async {
          if (!serverPaired.isCompleted) serverPaired.complete(peer);
        },
        onClip: (_) async {},
        onClosed: (_, _) {},
      );
      serverConnected.complete(connection);
      return connection;
    }();

    final clientConnection = await PeerConnection.connect(
      host: InternetAddress.loopbackIPv4.address,
      port: serverSocket.port,
      identity: _identity(_client, 'Client iPhone', 'ios'),
      mode: ConnectionMode.code,
      pairingCode: code.code,
      onPeerPaired: (peer, _) async {
        if (!clientPaired.isCompleted) clientPaired.complete(peer);
      },
      onClip: (_) async {},
      onClosed: (_, _) {},
    );
    final serverConnection = await serverConnected.future;
    addTearDown(() async {
      await clientConnection.close();
      await serverConnection.close();
      await serverSocket.close();
    });

    final clientPeer = await clientPaired.future;
    final serverPeer = await serverPaired.future;
    expect(clientPeer.secret, serverPeer.secret);
    expect(codes.active, isNull, reason: 'one-time code must be consumed');
    expect(serverPeer.id, _client);

    await clientConnection.close();
    await serverConnection.close();

    final reconnectListener =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final reconnectServerConnected = Completer<PeerConnection>();
    final serverReconnectTask = () async {
      final socket =
          await reconnectListener.first.timeout(const Duration(seconds: 5));
      final connection = await PeerConnection.accept(
        socket: socket,
        identity: _identity(_server, 'Server PC', 'windows'),
        findPaired: (id) => id == serverPeer.id ? serverPeer : null,
        pairingCodes: PairingCodeStore(),
        approvePairing: (_) async => true,
        onPeerPaired: (_, _) async {},
        onClip: (_) async {},
        onClosed: (_, _) {},
      );
      reconnectServerConnected.complete(connection);
      return connection;
    }();

    final reconnectedClient = await PeerConnection.connect(
      host: InternetAddress.loopbackIPv4.address,
      port: reconnectListener.port,
      identity: _identity(_client, 'Client iPhone', 'ios'),
      mode: ConnectionMode.connect,
      knownPeer: clientPeer,
      expectedPeerId: _server,
      onPeerPaired: (_, _) async {},
      onClip: (_) async {},
      onClosed: (_, _) {},
    );
    final reconnectedServer = await reconnectServerConnected.future;
    expect(reconnectedClient.peer.id, _server);
    expect(reconnectedClient.peer.name, 'Server PC');

    await reconnectedClient.close();
    await reconnectedServer.close();
    await reconnectListener.close();
    await serverTask.catchError((Object _) => serverConnection);
    await serverReconnectTask.catchError((Object _) => reconnectedServer);
  });

  test('wrong pairing code is rejected', () async {
    final serverSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final codes = PairingCodeStore();
    final entry = codes.generate();
    final serverFailure = Completer<Object>();
    final serverTask = () async {
      final socket = await serverSocket.first.timeout(const Duration(seconds: 5));
      try {
        await PeerConnection.accept(
          socket: socket,
          identity: _identity(_server, 'Server PC', 'windows'),
          findPaired: (_) => null,
          pairingCodes: codes,
          approvePairing: (_) async => true,
          onPeerPaired: (_, _) async {},
          onClip: (_) async {},
          onClosed: (_, _) {},
        );
      } catch (error) {
        if (!serverFailure.isCompleted) serverFailure.complete(error);
      }
    }();

    final badCode = entry.code == 'AAAAAAAA' ? 'BBBBBBBB' : 'AAAAAAAA';
    await expectLater(
      PeerConnection.connect(
        host: InternetAddress.loopbackIPv4.address,
        port: serverSocket.port,
        identity: _identity(_client, 'Client', 'android'),
        mode: ConnectionMode.code,
        pairingCode: badCode,
        onPeerPaired: (_, _) async {},
        onClip: (_) async {},
        onClosed: (_, _) {},
      ),
      throwsA(isA<PeerProtocolException>()),
    );
    final error = await serverFailure.future.timeout(const Duration(seconds: 5));
    expect(error, isA<PeerProtocolException>());
    expect(codes.active, isNotNull, reason: 'failed pairing must not consume code');
    await serverSocket.close();
    await serverTask;
  });
}
