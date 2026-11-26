import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cliplink/core/models.dart';
import 'package:cliplink/network/discovery_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UDP discovery receives and validates a peer announcement', () async {
    final events = <List<PeerPresence>>[];
    final firstPeer = Completer<PeerPresence>();
    const port = 49217;
    final local = LocalIdentity(
      id: '11111111111111111111111111111111',
      name: 'Local PC',
      platform: 'windows',
    );
    final service = DiscoveryService(
      identity: local,
      tcpPort: 47820,
      discoveryPort: port,
      onPeersChanged: (peers) {
        events.add(peers);
        if (peers.isNotEmpty && !firstPeer.isCompleted) {
          firstPeer.complete(peers.single);
        }
      },
    );
    addTearDown(service.stop);
    await service.start();

    final sender = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(sender.close);
    final peerId = 'b' * 32;
    final packet = Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'magic': kDiscoveryMagic,
          'v': 1,
          'id': peerId,
          'name': 'Remote Mac',
          'platform': 'macos',
          'port': 47821,
          'ips': <String>['192.168.1.50'],
        }),
      ),
    );

    // UDP is lossy; resend a few times while waiting for the callback.
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!firstPeer.isCompleted && DateTime.now().isBefore(deadline)) {
      sender.send(packet, InternetAddress.loopbackIPv4, port);
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }

    final peer = await firstPeer.future.timeout(const Duration(seconds: 2));
    expect(peer.id, peerId);
    expect(peer.name, 'Remote Mac');
    expect(peer.platform, 'macos');
    expect(peer.port, 47821);
    expect(peer.addresses, contains('192.168.1.50'));
    expect(events, isNotEmpty);
  });
}
