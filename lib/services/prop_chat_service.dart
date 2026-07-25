import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class PropChatMessage {
  const PropChatMessage({
    required this.id,
    required this.userId,
    required this.username,
    required this.body,
    required this.createdAt,
  });

  final int id;
  final String userId;
  final String username;
  final String body;
  final DateTime createdAt;

  factory PropChatMessage.fromJson(Map<String, dynamic> json) {
    return PropChatMessage(
      id: (json['id'] as num?)?.toInt() ?? 0,
      userId: json['user_id']?.toString() ?? '',
      username: json['username']?.toString() ?? 'member',
      body: json['body']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }
}

class PropChatService {
  SupabaseClient? get _client => SupabaseService.client;

  String? get currentUserId => _client?.auth.currentUser?.id;

  Stream<List<PropChatMessage>> watchMessages() {
    final client = _client;
    if (client == null || currentUserId == null) {
      return Stream<List<PropChatMessage>>.value(const []);
    }
    return client
        .from('prop_chat_messages')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .limit(200)
        .map(
          (rows) => rows
              .map((row) => PropChatMessage.fromJson(row))
              .toList(growable: false),
        );
  }

  Future<Set<String>> loadBlockedUserIds() async {
    final client = _client;
    final userId = currentUserId;
    if (client == null || userId == null) return const {};
    final rows = await client
        .from('prop_chat_blocks')
        .select('blocked_id')
        .eq('blocker_id', userId);
    return (rows as List)
        .map((row) => (row as Map<String, dynamic>)['blocked_id']?.toString())
        .whereType<String>()
        .toSet();
  }

  Future<void> sendMessage(String body) async {
    final client = _client;
    final userId = currentUserId;
    final trimmed = body.trim();
    if (client == null || userId == null) {
      throw StateError('Sign in to use PROP CHAT.');
    }
    if (trimmed.isEmpty || trimmed.length > 500) {
      throw ArgumentError('Messages must contain 1–500 characters.');
    }
    await client.from('prop_chat_messages').insert({
      'user_id': userId,
      'username': 'server-assigned',
      'body': trimmed,
    });
  }

  Future<void> deleteMessage(int messageId) async {
    final client = _client;
    if (client == null) throw StateError('PROP CHAT is unavailable.');
    await client.from('prop_chat_messages').delete().eq('id', messageId);
  }

  Future<void> reportMessage(int messageId, String reason) async {
    final client = _client;
    final userId = currentUserId;
    if (client == null || userId == null) {
      throw StateError('Sign in to report a message.');
    }
    await client.from('prop_chat_reports').upsert({
      'message_id': messageId,
      'reporter_id': userId,
      'reason': reason.trim(),
    });
  }

  Future<void> blockUser(String blockedUserId) async {
    final client = _client;
    final userId = currentUserId;
    if (client == null || userId == null) {
      throw StateError('Sign in to block a user.');
    }
    await client.from('prop_chat_blocks').upsert({
      'blocker_id': userId,
      'blocked_id': blockedUserId,
    });
  }
}
