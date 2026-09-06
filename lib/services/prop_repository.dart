import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/prop_page.dart';

typedef PropPageLoader = Future<PropPage> Function(PropQuery query);

class ObsoletePropRequest implements Exception {
  const ObsoletePropRequest();
}

class PropPageState {
  const PropPageState({
    required this.query,
    this.page,
    this.status = PropPageStatus.idle,
    this.error,
  });

  final PropQuery query;
  final PropPage? page;
  final PropPageStatus status;
  final Object? error;

  PropPageState copyWith({
    PropPage? page,
    PropPageStatus? status,
    Object? error,
    bool clearError = false,
  }) => PropPageState(
    query: query,
    page: page ?? this.page,
    status: status ?? this.status,
    error: clearError ? null : error ?? this.error,
  );
}

class PropPageSubscription {
  PropPageSubscription(this.state, this._release);

  final ValueListenable<PropPageState> state;
  final VoidCallback _release;
  bool _released = false;

  void dispose() {
    if (_released) return;
    _released = true;
    _release();
  }
}

class PropRepository {
  PropRepository({required PropPageLoader loader, int maxEntries = 12})
    : this._withLoader(loader, maxEntries);

  PropRepository._withLoader(this._loader, this.maxEntries);

  final PropPageLoader _loader;
  final int maxEntries;
  final LinkedHashMap<String, PropPage> _cache = LinkedHashMap();
  final Map<String, Future<PropPage>> _inFlight = {};
  final Map<String, ValueNotifier<PropPageState>> _states = {};
  final Map<String, int> _references = {};
  int _generation = 0;
  String _scope = '';

  int get cacheSize => _cache.length;
  int get inFlightCount => _inFlight.length;
  Iterable<PropQuery> get activeQueries => _states.entries
      .where((entry) => (_references[entry.key] ?? 0) > 0)
      .map((entry) => entry.value.value.query);

  void setScope(String scope) {
    if (_scope == scope) return;
    _scope = scope;
    _generation++;
    _cache.clear();
    _inFlight.clear();
    for (final notifier in _states.values) {
      notifier.value = PropPageState(query: notifier.value.query);
    }
  }

  PropPageSubscription subscribe(PropQuery query) {
    _requireScope(query);
    final notifier = _states.putIfAbsent(
      query.key,
      () => ValueNotifier(PropPageState(query: query, page: _cache[query.key])),
    );
    _references[query.key] = (_references[query.key] ?? 0) + 1;
    return PropPageSubscription(notifier, () {
      final remaining = (_references[query.key] ?? 1) - 1;
      if (remaining <= 0) {
        _references.remove(query.key);
      } else {
        _references[query.key] = remaining;
      }
    });
  }

  PropPage? cached(PropQuery query) {
    _requireScope(query);
    final page = _cache.remove(query.key);
    if (page != null) _cache[query.key] = page;
    return page;
  }

  Future<PropPage> load(PropQuery query, {bool force = false}) {
    _requireScope(query);
    if (!force) {
      final cachedPage = cached(query);
      if (cachedPage != null) return SynchronousFuture(cachedPage);
    }
    return _inFlight.putIfAbsent(query.key, () => _performLoad(query));
  }

  Future<PropPage> _performLoad(PropQuery query) async {
    final requestGeneration = _generation;
    final notifier = _states[query.key];
    final previous = notifier?.value.page ?? _cache[query.key];
    if (notifier != null) {
      notifier.value = PropPageState(
        query: query,
        page: previous,
        status: previous == null
            ? PropPageStatus.checking
            : PropPageStatus.updating,
      );
    }
    try {
      final page = await _loader(query);
      if (requestGeneration != _generation || query.accessScope != _scope) {
        throw const ObsoletePropRequest();
      }
      if (page.query.key != query.key) {
        throw StateError('Prop response query does not match its request.');
      }
      _cache.remove(query.key);
      _cache[query.key] = page;
      while (_cache.length > maxEntries) {
        _cache.remove(_cache.keys.first);
      }
      if (notifier != null) {
        notifier.value = PropPageState(
          query: query,
          page: page,
          status: page.status,
        );
      }
      return page;
    } on ObsoletePropRequest {
      rethrow;
    } catch (error) {
      if (requestGeneration != _generation) throw const ObsoletePropRequest();
      if (notifier != null) {
        notifier.value = PropPageState(
          query: query,
          page: previous,
          status: previous == null
              ? PropPageStatus.reconnecting
              : PropPageStatus.offlineSaved,
          error: error,
        );
      }
      rethrow;
    } finally {
      _inFlight.remove(query.key);
    }
  }

  void _requireScope(PropQuery query) {
    if (_scope.isEmpty) _scope = query.accessScope;
    if (query.accessScope != _scope) {
      throw StateError('Prop query belongs to a different account scope.');
    }
  }

  void dispose() {
    _generation++;
    _cache.clear();
    _inFlight.clear();
    for (final notifier in _states.values) {
      notifier.dispose();
    }
    _states.clear();
    _references.clear();
  }
}
