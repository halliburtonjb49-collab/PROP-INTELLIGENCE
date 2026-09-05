import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/scoreboard_game.dart';
import '../services/scoreboard_service.dart';
import '../services/live_update_service.dart';

class ScoreboardController extends ChangeNotifier {
  ScoreboardController({required ScoreboardService service})
    : _service = service,
      _games = service.cachedGames(DateTime.now());

  final ScoreboardService _service;

  List<ScoreboardGame> _games;
  bool _isLoading = false;
  bool _isRefreshing = false;
  String? _errorMessage;
  DateTime _selectedDate = DateTime.now();
  Timer? _refreshTimer;
  late final LiveUpdateService _liveUpdates = LiveUpdateService(
    channels: const {'scoreboard'},
  );
  StreamSubscription<dynamic>? _liveSubscription;

  List<ScoreboardGame> get games => List.unmodifiable(_games);
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  String? get errorMessage => _errorMessage;
  DateTime get selectedDate => _selectedDate;

  Future<void> load({bool silent = false}) async {
    if (_isLoading || _isRefreshing) {
      return;
    }

    if (silent) {
      _isRefreshing = true;
    } else {
      _isLoading = true;
    }

    _errorMessage = null;
    notifyListeners();

    try {
      final incoming = await _fetchGamesWithRetry();
      // A background provider refresh can briefly return an empty slate while
      // upstream schedules are being rebuilt. Never flash away a verified
      // same-day scoreboard during silent polling; a manual/date-changing
      // load can still intentionally show a genuinely empty day.
      if (incoming.isNotEmpty || !silent || _games.isEmpty) {
        _games = incoming;
      }
    } catch (error) {
      if (silent) {
        _errorMessage = null;
      } else {
        _errorMessage = _formatErrorMessage(error);
      }
    } finally {
      _isLoading = false;
      _isRefreshing = false;
      notifyListeners();
    }
  }

  Future<List<ScoreboardGame>> _fetchGamesWithRetry() async {
    Object? lastError;
    // One quick retry keeps a transient mobile handoff recoverable without
    // making the user wait through three full network timeouts (~30 seconds).
    const retryDelays = <Duration>[Duration(milliseconds: 500)];

    for (var attempt = 0; attempt <= retryDelays.length; attempt++) {
      try {
        return await _service.fetchGames(date: _selectedDate);
      } catch (error) {
        lastError = error;
        if (attempt == retryDelays.length) rethrow;
        await Future<void>.delayed(retryDelays[attempt]);
      }
    }

    throw lastError ?? Exception('Unable to load live scores.');
  }

  String _formatErrorMessage(Object error) {
    if (error is TimeoutException) {
      return 'Live scores are taking longer than expected. Please retry.';
    }
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    if (message.length <= 140) {
      return message;
    }
    return '${message.substring(0, 140)}...';
  }

  Future<void> previousDay() async {
    _selectedDate = _selectedDate.subtract(const Duration(days: 1));
    notifyListeners();
    await load();
  }

  Future<void> nextDay() async {
    _selectedDate = _selectedDate.add(const Duration(days: 1));
    notifyListeners();
    await load();
  }

  Future<void> goToToday() async {
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    notifyListeners();
    await load();
  }

  Future<void> selectDate(DateTime value) async {
    _selectedDate = DateTime(value.year, value.month, value.day);
    notifyListeners();
    await load();
  }

  void beginLiveRefresh() {
    _liveSubscription ??= _liveUpdates.stream.listen(
      _handleLiveEvent,
      onError: (_) {},
    );
    _liveUpdates.connect();
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final now = DateTime.now();
      final isToday =
          _selectedDate.year == now.year &&
          _selectedDate.month == now.month &&
          _selectedDate.day == now.day;
      final hasLiveGames = _games.any((game) => game.isLive);
      if (isToday || hasLiveGames) {
        load(silent: true);
      }
    });
  }

  void stopLiveRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void _handleLiveEvent(dynamic raw) {
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is! Map || decoded['type'] != 'scoreboard.updated') return;
      final data = decoded['data'];
      if (data is! Map || data['games'] is! List) return;
      final eventDate = DateTime.tryParse(data['date']?.toString() ?? '');
      if (eventDate == null ||
          eventDate.year != _selectedDate.year ||
          eventDate.month != _selectedDate.month ||
          eventDate.day != _selectedDate.day) {
        return;
      }
      final incoming = (data['games'] as List)
          .whereType<Map>()
          .map((row) => ScoreboardGame.fromJson(Map<String, dynamic>.from(row)))
          .toList(growable: false);
      // Live invalidation messages may arrive between the provider's delete
      // and repopulate phases. Preserve the last verified slate until the
      // replacement message contains games.
      if (incoming.isEmpty && _games.isNotEmpty) return;
      _games = incoming;
      _errorMessage = null;
      notifyListeners();
    } catch (_) {
      // The regular 30-second refresh remains the authoritative fallback.
    }
  }

  @override
  void dispose() {
    stopLiveRefresh();
    unawaited(_liveSubscription?.cancel());
    unawaited(_liveUpdates.dispose());
    super.dispose();
  }
}
