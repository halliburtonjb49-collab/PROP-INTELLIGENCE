import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_service.dart';
import 'supabase_service.dart';

@visibleForTesting
abstract interface class LiveSocket {
  Stream<dynamic> get stream;
  void add(dynamic event);
  Future<void> close();
}

class _WebSocketLiveSocket implements LiveSocket {
  _WebSocketLiveSocket(Uri uri) : _channel = WebSocketChannel.connect(uri);

  final WebSocketChannel _channel;

  @override
  Stream<dynamic> get stream => _channel.stream;

  @override
  void add(dynamic event) => _channel.sink.add(event);

  @override
  Future<void> close() async => _channel.sink.close();
}

typedef LiveSocketConnector = LiveSocket Function(Uri uri);

class LiveUpdateService {
  LiveUpdateService({
    this.channels = const {'props'},
    this.protocolVersion = 1,
    LiveSocketConnector? connector,
  }) : _connector = connector ?? _WebSocketLiveSocket.new,
       _connectorWasInjected = connector != null;

  final Set<String> channels;
  final int protocolVersion;
  final LiveSocketConnector _connector;
  final bool _connectorWasInjected;
  final StreamController<dynamic> _events = StreamController.broadcast();
  LiveSocket? _channel;
  Timer? _reconnectTimer;
  bool _closed = false;
  bool _paused = false;
  int _attempt = 0;

  Stream<dynamic> get stream => _events.stream;

  void connect() {
    if (_closed || _paused || _channel != null) return;
    // The production API currently exposes low-rate HTTP reconciliation, but
    // no WebSocket route. Repeatedly connecting to the missing route generated
    // a 404 loop from every mounted panel and competed with the first prop
    // request on mobile. Keep injected sockets available to tests and make the
    // production socket an explicit build-time opt-in when the route exists.
    const productionSocketEnabled = bool.fromEnvironment(
      'PI_REALTIME_SOCKET_ENABLED',
      defaultValue: false,
    );
    if (!_connectorWasInjected && !productionSocketEnabled) return;
    if (kDebugMode && !SupabaseService.isConfigured && !_connectorWasInjected) {
      return;
    }
    final configuredBase = ApiService.baseUrl.trim();
    if (configuredBase.isEmpty) return;
    final httpBase = Uri.tryParse(configuredBase);
    if (httpBase == null || !httpBase.hasScheme || httpBase.host.isEmpty) {
      return;
    }
    final uri = httpBase.replace(
      scheme: httpBase.scheme == 'https' ? 'wss' : 'ws',
      path: '/api/realtime/ws',
      queryParameters: {
        'channels': channels.join(','),
        if (protocolVersion > 1) 'protocol': '$protocolVersion',
      },
    );
    try {
      final channel = _connector(uri);
      _channel = channel;
      channel.stream.listen(
        (event) {
          if (!identical(_channel, channel)) return;
          _attempt = 0;
          if (event.toString().contains('authentication.required')) {
            final token =
                SupabaseService.client?.auth.currentSession?.accessToken;
            if (token != null) {
              channel.add('{"type":"authenticate","token":"$token"}');
            }
            return;
          }
          _events.add(event);
        },
        onError: (Object error) => _handleDisconnect(channel, error),
        onDone: () => _handleDisconnect(channel),
        cancelOnError: true,
      );
    } catch (error) {
      _handleDisconnect(null, error);
    }
  }

  void _handleDisconnect(LiveSocket? owner, [Object? error]) {
    if (owner != null && !identical(_channel, owner)) return;
    final channel = _channel;
    _channel = null;
    unawaited(channel?.close());
    if (error != null && !_events.isClosed) _events.addError(error);
    if (_closed || _paused || _reconnectTimer != null) return;
    final exponent = _attempt > 5 ? 5 : _attempt;
    final delay = Duration(seconds: 1 << exponent);
    _attempt++;
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      connect();
    });
  }

  Future<void> pause() async {
    if (_closed || _paused) return;
    _paused = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final channel = _channel;
    _channel = null;
    await channel?.close();
  }

  void resume() {
    if (_closed || !_paused) return;
    _paused = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(milliseconds: 100), () {
      _reconnectTimer = null;
      connect();
    });
  }

  Future<void> dispose() async {
    _closed = true;
    _reconnectTimer?.cancel();
    await _channel?.close();
    await _events.close();
  }
}
