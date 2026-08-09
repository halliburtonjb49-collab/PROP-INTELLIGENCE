import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_service.dart';

class EngagementTracker {
  EngagementTracker._();
  static final EngagementTracker instance = EngagementTracker._();

  final ApiService _api = ApiService();
  final List<Map<String, String>> _queue = [];
  Timer? _timer;
  bool _flushing = false;

  void record(String propId, String action) {
    if (propId.trim().isEmpty) return;
    _queue.add({'prop_id': propId, 'action': action});
    if (_queue.length > 100) _queue.removeAt(0);
    _timer ??= Timer(const Duration(seconds: 5), flush);
    if (_queue.length >= 20) unawaited(flush());
  }

  void recordProduct(String action) {
    if (!kReleaseMode) return;
    final normalized = action.trim().toUpperCase();
    if (normalized.isEmpty) return;
    record('__PRODUCT__', normalized);
  }

  void recordError(Object error) {
    if (!kReleaseMode) return;
    final fingerprint = error.runtimeType
        .toString()
        .replaceAll(RegExp(r'[^A-Za-z0-9_]'), '')
        .toUpperCase();
    record(
      '__ERROR__:${fingerprint.isEmpty ? 'UNKNOWN' : fingerprint}',
      'ERROR',
    );
  }

  Future<void> flush() async {
    if (_flushing || _queue.isEmpty) return;
    _timer?.cancel();
    _timer = null;
    _flushing = true;
    final batch = _queue.take(100).toList(growable: false);
    try {
      await _api.recordEngagement(batch);
      _queue.removeRange(0, batch.length);
    } catch (_) {
      // Retain the batch for a later authenticated/network retry.
    } finally {
      _flushing = false;
      if (_queue.isNotEmpty) _timer = Timer(const Duration(seconds: 15), flush);
    }
  }
}
