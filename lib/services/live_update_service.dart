import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_service.dart';
import 'supabase_service.dart';

class LiveUpdateService {
  LiveUpdateService({this.channels = const {'props'}});

  final Set<String> channels;
  final StreamController<dynamic> _events = StreamController.broadcast();
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  bool _closed = false;
  int _attempt = 0;

  Stream<dynamic> get stream => _events.stream;

  void connect() {
    if (_closed || _channel != null) return;
    final httpBase = Uri.parse(ApiService.baseUrl);
    final uri = httpBase.replace(
      scheme: httpBase.scheme == 'https' ? 'wss' : 'ws',
      path: '/api/realtime/ws',
      queryParameters: {'channels': channels.join(',')},
    );
    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      channel.stream.listen(
        (event) {
          _attempt = 0;
          if (event.toString().contains('authentication.required')) {
            final token =
                SupabaseService.client?.auth.currentSession?.accessToken;
            if (token != null) {
              channel.sink.add('{"type":"authenticate","token":"$token"}');
            }
            return;
          }
          _events.add(event);
        },
        onError: _handleDisconnect,
        onDone: _handleDisconnect,
        cancelOnError: true,
      );
    } catch (error) {
      _handleDisconnect(error);
    }
  }

  void _handleDisconnect([Object? error]) {
    _channel?.sink.close();
    _channel = null;
    if (error != null && !_events.isClosed) _events.addError(error);
    if (_closed || _reconnectTimer != null) return;
    final exponent = _attempt > 5 ? 5 : _attempt;
    final delay = Duration(seconds: 1 << exponent);
    _attempt++;
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      connect();
    });
  }

  Future<void> dispose() async {
    _closed = true;
    _reconnectTimer?.cancel();
    await _channel?.sink.close();
    await _events.close();
  }
}
