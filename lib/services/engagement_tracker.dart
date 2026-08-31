import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_service.dart';

class EngagementTracker {
  EngagementTracker._();
  static final EngagementTracker instance = EngagementTracker._();

  final ApiService _api = ApiService();
  final List<Map<String, dynamic>> _queue = [];
  Timer? _timer;
  bool _flushing = false;
  final Map<String, DateTime> _lastProductEvent = {};
  DateTime? _appOpenedAt;

  void record(String propId, String action) {
    if (propId.trim().isEmpty) return;
    _queue.add({'prop_id': propId, 'action': action});
    if (_queue.length > 100) _queue.removeAt(0);
    _timer ??= Timer(const Duration(seconds: 5), flush);
    if (_queue.length >= 20) unawaited(flush());
  }

  void recordOperational(String action, {String endpoint = '', String category = '',
    String provider = '', String mediaType = '', int? durationMs}) {
    if (!kReleaseMode) return;
    String safe(String value) {
      final cleaned = value.split('?').first.replaceAll(RegExp(r'[^A-Za-z0-9_./:-]'), '_');
      return cleaned.length <= 160 ? cleaned : cleaned.substring(0, 160);
    }
    _queue.add({
      'prop_id': '__OBSERVABILITY__', 'action': action.trim().toUpperCase(),
      if (durationMs != null) 'duration_ms': durationMs.clamp(0, 300000),
      'metadata': <String, String>{
        'release': ApiService.appVersion,
        'device': kIsWeb ? 'web' : defaultTargetPlatform.name,
        if (endpoint.isNotEmpty) 'endpoint': safe(endpoint),
        if (category.isNotEmpty) 'category': safe(category),
        if (provider.isNotEmpty) 'provider': safe(provider),
        if (mediaType.isNotEmpty) 'mediaType': safe(mediaType),
      },
    });
    if (_queue.length > 100) _queue.removeAt(0);
    _timer ??= Timer(const Duration(seconds: 5), flush);
  }

  void recordProduct(String action) {
    if (!kReleaseMode) return;
    final normalized = action.trim().toUpperCase();
    if (normalized.isEmpty) return;
    if (normalized == 'APP_OPEN') {
      _appOpenedAt = DateTime.now();
      recordOperational('SERVICE_WORKER_VERSION', endpoint: '/workspace');
    } else if (normalized == 'DASHBOARD_READY' && _appOpenedAt != null) {
      recordOperational(
        'SCREEN_TIMING', endpoint: '/workspace', category: 'cached_content',
        durationMs: DateTime.now().difference(_appOpenedAt!).inMilliseconds,
      );
    }
    record('__PRODUCT__', normalized);
  }

  void recordProductOncePer(String action, Duration window) {
    final normalized = action.trim().toUpperCase();
    final now = DateTime.now();
    final last = _lastProductEvent[normalized];
    if (last != null && now.difference(last) < window) return;
    _lastProductEvent[normalized] = now;
    recordProduct(normalized);
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
    if (fingerprint.contains('AUTH')) {
      recordOperational('AUTH_FAILURE', endpoint: '/login', category: fingerprint);
    }
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
