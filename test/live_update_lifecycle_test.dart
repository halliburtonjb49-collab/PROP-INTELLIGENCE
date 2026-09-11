import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/services/live_update_service.dart';

class _FakeSocket implements LiveSocket {
  _FakeSocket({required this.closeImmediately});

  final bool closeImmediately;
  final StreamController<dynamic> controller = StreamController<dynamic>();
  final Completer<void> closeCompleter = Completer<void>();
  final List<dynamic> sent = [];

  @override
  Stream<dynamic> get stream => controller.stream;

  @override
  void add(dynamic event) => sent.add(event);

  @override
  Future<void> close() {
    if (closeImmediately) finishClose();
    return closeCompleter.future;
  }

  void finishClose() {
    if (!closeCompleter.isCompleted) closeCompleter.complete();
    if (!controller.isClosed) unawaited(controller.close());
  }
}

void main() {
  test(
    'late close from paused socket cannot disconnect resumed socket',
    () async {
      final sockets = <_FakeSocket>[];
      final service = LiveUpdateService(
        connector: (_) {
          final socket = _FakeSocket(closeImmediately: sockets.isNotEmpty);
          sockets.add(socket);
          return socket;
        },
      );
      final received = <dynamic>[];
      final subscription = service.stream.listen(received.add);

      service.connect();
      expect(sockets, hasLength(1));

      final pauseFuture = service.pause();
      service.resume();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(sockets, hasLength(2));

      sockets.first.finishClose();
      await pauseFuture;
      await Future<void>.delayed(Duration.zero);

      sockets.last.controller.add('{"type":"props.revision"}');
      await Future<void>.delayed(Duration.zero);
      expect(received, ['{"type":"props.revision"}']);
      expect(sockets, hasLength(2));

      await subscription.cancel();
      await service.dispose();
    },
  );
}
