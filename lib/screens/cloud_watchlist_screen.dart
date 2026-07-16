import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/auth_manager.dart';
import '../services/api_service.dart';
import '../widgets/watchlist_view.dart';

class CloudWatchlistScreen extends StatefulWidget {
  const CloudWatchlistScreen({super.key});

  @override
  State<CloudWatchlistScreen> createState() => _CloudWatchlistScreenState();
}

class _CloudWatchlistScreenState extends State<CloudWatchlistScreen> {
  final ApiService _apiService = ApiService();
  Stream<dynamic>? _channelStream;
  bool _websocketUnavailable = false;
  Timer? _fallbackPollTimer;

  List<dynamic> _fetchedProps = const [];

  @override
  void initState() {
    super.initState();
    _websocketUnavailable = true;
    _startFallbackPolling();
  }

  Future<void> _fetchFallbackProps() async {
    try {
      final incoming = await _apiService.fetchRawPropsFeed();
      if (!mounted) {
        return;
      }
      setState(() {
        _fetchedProps = incoming;
      });
    } catch (_) {
      // Keep fallback polling quiet to avoid user-facing noise.
    }
  }

  void _startFallbackPolling() {
    if (_fallbackPollTimer != null) {
      return;
    }
    _fetchFallbackProps();
    _fallbackPollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _fetchFallbackProps();
    });
  }

  @override
  void dispose() {
    _fallbackPollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AuthSessionState>(
      valueListenable: AuthManager.instance.sessionState,
      builder: (context, authState, _) {
        return StreamBuilder(
          stream: _channelStream,
          builder: (context, snapshot) {
            if (snapshot.hasError && !_websocketUnavailable) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) {
                  return;
                }
                setState(() {
                  _websocketUnavailable = true;
                });
              });
            }

            if (snapshot.hasData) {
              final decoded = jsonDecode(snapshot.data.toString());
              if (decoded is List) {
                _fetchedProps = decoded;
              }
            }

            if (_fetchedProps.isEmpty) {
              return Center(
                child: Text(
                  _websocketUnavailable
                      ? 'Live websocket unavailable. Polling API every 10s.'
                      : 'Connecting to Python Server Engine...',
                  style: const TextStyle(color: Colors.grey),
                ),
              );
            }

            return CloudWatchlistDashboardCanvas(
              globalLiveProps: _fetchedProps,
              isUserPremium: authState.isPremium,
            );
          },
        );
      },
    );
  }
}
