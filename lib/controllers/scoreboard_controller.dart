import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/scoreboard_game.dart';
import '../services/scoreboard_service.dart';

class ScoreboardController extends ChangeNotifier {
  ScoreboardController({required this._service});

  final ScoreboardService _service;

  List<ScoreboardGame> _games = [];
  bool _isLoading = false;
  bool _isRefreshing = false;
  String? _errorMessage;
  DateTime _selectedDate = DateTime.now();
  Timer? _refreshTimer;

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
      final incoming = await _service.fetchGames(date: _selectedDate);
      _games = incoming;
    } catch (error) {
      if (_games.isNotEmpty && silent) {
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

  String _formatErrorMessage(Object error) {
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

  void beginLiveRefresh() {
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

  @override
  void dispose() {
    stopLiveRefresh();
    super.dispose();
  }
}
