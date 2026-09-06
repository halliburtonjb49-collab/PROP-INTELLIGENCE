import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../config/pi_sync_flags.dart';
import '../models/prop_page.dart';
import 'api_service.dart';
import 'live_update_service.dart';
import 'prop_repository.dart';

class PropSyncCoordinator {
  PropSyncCoordinator({
    required this.repository,
    required String initialScope,
    this.reconcileInterval = const Duration(seconds: 60),
    bool? revisionFeedEnabledOverride,
  }) : _scope = initialScope {
    repository.setScope(initialScope);
    if (propRevisionFeedEnabled(override: revisionFeedEnabledOverride)) {
      _liveUpdates = LiveUpdateService(
        channels: const {'props'},
        protocolVersion: 2,
      );
      _liveSubscription = _liveUpdates!.stream.listen(_handleLiveEvent);
      _liveUpdates!.connect();
    }
  }

  final PropRepository repository;
  final Duration reconcileInterval;
  String _scope;
  Timer? _reconcileTimer;
  Timer? _coalesceTimer;
  bool _foreground = true;
  bool _disposed = false;
  Future<void>? _reconcileInFlight;
  LiveUpdateService? _liveUpdates;
  StreamSubscription<dynamic>? _liveSubscription;
  String _lastRevision = '';
  String _lastEpoch = '';
  int _lastSequence = -1;
  String? _pendingAppliedRevision;
  DateTime? _pendingPublishedAt;

  String get scope => _scope;

  PropPageSubscription subscribe(PropQuery query) {
    if (query.accessScope != _scope) {
      throw StateError('Subscription scope does not match the active session.');
    }
    final subscription = repository.subscribe(query);
    _ensureTimer();
    return subscription;
  }

  Future<PropPage> load(PropQuery query, {bool force = false}) =>
      repository.load(query, force: force);

  void invalidate({Duration delay = const Duration(milliseconds: 150)}) {
    if (_disposed || !_foreground) return;
    _coalesceTimer?.cancel();
    _coalesceTimer = Timer(delay, () => unawaited(reconcile()));
  }

  Future<void> updateScope(String nextScope) async {
    if (_disposed || nextScope == _scope) return;
    _scope = nextScope;
    _coalesceTimer?.cancel();
    _reconcileTimer?.cancel();
    repository.setScope(nextScope);
    await ApiService.invalidateProtectedCaches();
    _ensureTimer();
  }

  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (!foreground) {
      _coalesceTimer?.cancel();
      _reconcileTimer?.cancel();
      unawaited(_liveUpdates?.pause());
      return;
    }
    _liveUpdates?.resume();
    _ensureTimer();
    unawaited(reconcile());
  }

  void _handleLiveEvent(dynamic raw) {
    try {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is! Map) return;
      final type = '${decoded['type'] ?? ''}';
      if (type != 'props.revision' && type != 'connection.ready') return;
      final manifest = decoded['manifest'];
      if (manifest is! Map) return;
      final revision = '${manifest['contentRevision'] ?? ''}';
      if (revision.isEmpty || revision == _lastRevision) return;
      final epoch = '${manifest['epoch'] ?? ''}';
      final sequence = manifest['sequence'] is num
          ? (manifest['sequence'] as num).toInt()
          : int.tryParse('${manifest['sequence'] ?? ''}');
      if (epoch.isNotEmpty &&
          epoch == _lastEpoch &&
          sequence != null &&
          sequence <= _lastSequence) {
        return;
      }
      _lastRevision = revision;
      if (epoch.isNotEmpty && sequence != null) {
        _lastEpoch = epoch;
        _lastSequence = sequence;
      }
      final publishedAt = DateTime.tryParse('${manifest['publishedAt'] ?? ''}');
      if (publishedAt != null) {
        _pendingAppliedRevision = revision;
        _pendingPublishedAt = publishedAt;
      }
      invalidate(delay: Duration.zero);
    } catch (_) {
      // A malformed hint is ignored; low-rate HTTP reconciliation remains.
    }
  }

  Future<void> reconcile() {
    if (_disposed || !_foreground) return Future.value();
    final active = repository.activeQueries.toList(growable: false);
    if (active.isEmpty) return Future.value();
    return _reconcileInFlight ??=
        Future.wait(
              active.map(
                (query) => repository.load(query, force: true).catchError((_) {
                  return repository.cached(query) ?? PropPage.empty(query);
                }),
              ),
            )
            .then<void>((_) {
              final revision = _pendingAppliedRevision;
              final publishedAt = _pendingPublishedAt;
              _pendingAppliedRevision = null;
              _pendingPublishedAt = null;
              if (revision != null && publishedAt != null) {
                unawaited(
                  ApiService().recordPropSyncApplied(
                    revision: revision,
                    publishedAt: publishedAt,
                    appliedAt: DateTime.now().toUtc(),
                  ),
                );
              }
            })
            .whenComplete(() => _reconcileInFlight = null);
  }

  void _ensureTimer() {
    if (_disposed || !_foreground || repository.activeQueries.isEmpty) return;
    _reconcileTimer ??= Timer.periodic(reconcileInterval, (_) {
      unawaited(reconcile());
    });
  }

  void dispose() {
    _disposed = true;
    _coalesceTimer?.cancel();
    _reconcileTimer?.cancel();
    unawaited(_liveSubscription?.cancel());
    unawaited(_liveUpdates?.dispose());
    repository.dispose();
  }
}
