import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../core/crypto.dart';

class WireFrame {
  WireFrame({required this.secure, required this.payload});

  final bool secure;
  final Uint8List payload;
}

class PeerLinkClosedException implements Exception {
  PeerLinkClosedException([this.message = '连接已关闭']);

  final String message;

  @override
  String toString() => message;
}

class FrameProtocolException implements Exception {
  FrameProtocolException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _InboundFrameDecoder {
  final List<Uint8List> _chunks = <Uint8List>[];
  int _available = 0;
  Uint8List? _body;
  int _bodyOffset = 0;

  void add(
    Uint8List data,
    void Function(WireFrame frame) onFrame,
  ) {
    if (data.isEmpty) return;
    _chunks.add(data);
    _available += data.length;
    while (true) {
      if (_body == null) {
        if (_available < 4) return;
        final header = _take(4);
        final declaredLength = ByteData.sublistView(header).getUint32(0);
        if (declaredLength < 1) {
          throw FrameProtocolException('Invalid frame length');
        }
        if (declaredLength > kMaxWireFrameBytes) {
          throw FrameProtocolException('Frame is too large');
        }
        _body = Uint8List(declaredLength);
        _bodyOffset = 0;
      }
      final body = _body!;
      if (_bodyOffset < body.length) {
        if (_available == 0) return;
        final chunk = _chunks.first;
        final take = min(body.length - _bodyOffset, chunk.length);
        body.setRange(_bodyOffset, _bodyOffset + take, chunk);
        _bodyOffset += take;
        _available -= take;
        if (take == chunk.length) {
          _chunks.removeAt(0);
        } else {
          _chunks[0] = Uint8List.sublistView(chunk, take);
        }
      }
      if (_bodyOffset == body.length) {
        final flag = body[0];
        final payload = Uint8List.sublistView(body, 1);
        _body = null;
        _bodyOffset = 0;
        onFrame(WireFrame(secure: flag == 1, payload: payload));
      }
    }
  }

  Uint8List _take(int count) {
    final output = Uint8List(count);
    var offset = 0;
    while (offset < count) {
      final chunk = _chunks.first;
      final take = min(count - offset, chunk.length);
      output.setRange(offset, offset + take, chunk);
      offset += take;
      _available -= take;
      if (take == chunk.length) {
        _chunks.removeAt(0);
      } else {
        _chunks[0] = Uint8List.sublistView(chunk, take);
      }
    }
    return output;
  }
}

/// One TCP connection with length-prefixed, optionally encrypted frames.
class PeerLink {
  PeerLink(this.socket) : remoteAddress = socket.remoteAddress.address, remotePort = socket.remotePort {
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}
    _subscription = socket.listen(
      _onData,
      onError: _onSocketError,
      onDone: _onSocketDone,
      cancelOnError: true,
    );
  }

  final Socket socket;
  final String remoteAddress;
  final int remotePort;
  final _InboundFrameDecoder _decoder = _InboundFrameDecoder();
  final Queue<WireFrame> _frames = Queue<WireFrame>();
  late final StreamSubscription<Uint8List> _subscription;
  Completer<WireFrame>? _waiter;
  Object? _error;
  bool _closed = false;
  Future<void> _sendTail = Future<void>.value();

  bool get isClosed => _closed;

  void _onData(Uint8List data) {
    try {
      _decoder.add(data, _deliver);
    } catch (error) {
      _fail(FrameProtocolException('Malformed frame: $error'));
      socket.destroy();
    }
  }

  void _deliver(WireFrame frame) {
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) {
      _waiter = null;
      waiter.complete(frame);
    } else {
      _frames.add(frame);
    }
  }

  void _onSocketError(Object error) {
    _fail(error);
  }

  void _onSocketDone() {
    _closed = true;
    if (_waiter != null && !_waiter!.isCompleted) {
      _waiter!.completeError(PeerLinkClosedException());
      _waiter = null;
    }
  }

  void _fail(Object error) {
    _closed = true;
    _error = error;
    if (_waiter != null && !_waiter!.isCompleted) {
      _waiter!.completeError(error);
      _waiter = null;
    }
  }

  Future<WireFrame> next({Duration timeout = const Duration(seconds: 15)}) {
    if (_frames.isNotEmpty) {
      return Future<WireFrame>.value(_frames.removeFirst());
    }
    if (_error != null) {
      return Future<WireFrame>.error(_error!);
    }
    if (_closed) {
      return Future<WireFrame>.error(PeerLinkClosedException());
    }
    final completer = Completer<WireFrame>();
    _waiter = completer;
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        if (identical(_waiter, completer)) _waiter = null;
        throw TimeoutException('等待对方响应超时', timeout);
      },
    );
  }

  Future<void> sendFrame({
    required bool secure,
    required List<int> payload,
  }) {
    final result = Completer<void>();
    _sendTail = _sendTail.then((_) async {
      if (_closed) throw PeerLinkClosedException();
      final frameLength = payload.length + 1;
      if (frameLength > kMaxWireFrameBytes) {
        throw FrameProtocolException('Frame is too large');
      }
      final header = ByteData(4)..setUint32(0, frameLength);
      final buffer = BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..addByte(secure ? 1 : 0)
        ..add(payload);
      socket.add(buffer.takeBytes());
      await socket.flush();
    }).then(
      (_) => result.complete(),
      onError: (Object error, StackTrace stackTrace) {
        result.completeError(error, stackTrace);
      },
    );
    return result.future;
  }

  Future<void> close() async {
    if (_closed) {
      try {
        socket.destroy();
      } catch (_) {}
      return;
    }
    _closed = true;
    try {
      await _subscription.cancel();
    } catch (_) {}
    try {
      socket.destroy();
    } catch (_) {}
    if (_waiter != null && !_waiter!.isCompleted) {
      _waiter!.completeError(PeerLinkClosedException());
      _waiter = null;
    }
  }
}
