import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/main.dart';

void main() {
  group('what the wait says about itself', () {
    test('a normal wait is quiet about it', () {
      expect(
        loadProgressMessage(const Duration(seconds: 1)),
        'Loading live props…',
      );
    });

    test('the message escalates as the wait becomes abnormal', () {
      final early = loadProgressMessage(
        const Duration(seconds: 1),
      );
      final middle = loadProgressMessage(
        const Duration(seconds: 6),
      );
      final late = loadProgressMessage(
        const Duration(seconds: 14),
      );
      final failing = loadProgressMessage(
        const Duration(seconds: 22),
      );

      expect({early, middle, late, failing}.length, 4);
    });

    test('a wait that is about to fail says what happens next', () {
      // The reader must not have to guess whether to keep waiting.
      final failing = loadProgressMessage(
        const Duration(seconds: 30),
      );

      expect(failing.toLowerCase(), contains('retry'));
    });
  });

  group('what a failure says about itself', () {
    test('a timeout is explained rather than dumped', () {
      final described = describeLoadFailure(
        TimeoutException('boom', const Duration(seconds: 25)),
      );

      // The mechanism is not the situation: never show the raw exception.
      expect(described, isNot(contains('TimeoutException')));
      expect(described, isNot(contains('0:00:25')));
      expect(described.toLowerCase(), contains('retry'));
    });

    test('a dropped connection is named as one', () {
      final described = describeLoadFailure(
        const SocketException('failed host lookup'),
      );

      expect(described.toLowerCase(), contains('connection'));
      expect(described, isNot(contains('SocketException')));
    });

    test('an unrecognised failure still says something', () {
      expect(describeLoadFailure(StateError('odd')), isNotEmpty);
      expect(describeLoadFailure(null), isNotEmpty);
    });
  });

  group('the feed is not waited on forever', () {
    test('the bound is generous enough not to fire on a working feed', () {
      // A bound tight enough to trip a slow-but-working backend would be a
      // worse defect than the hang it protects against.
      expect(propFetchTimeout.inSeconds, greaterThanOrEqualTo(15));
      expect(propFetchTimeout.inSeconds, lessThanOrEqualTo(60));
    });
  });
}
