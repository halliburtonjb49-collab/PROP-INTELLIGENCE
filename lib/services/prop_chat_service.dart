import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';
import 'app_sound_service.dart';

class PropChatRoom {
  const PropChatRoom({required this.id, required this.name});
  final String id;
  final String name;

  factory PropChatRoom.fromJson(Map<String, dynamic> json) => PropChatRoom(
    id: json['id']?.toString() ?? 'general',
    name: json['name']?.toString() ?? 'General',
  );
}

class PropChatMessage {
  const PropChatMessage({
    required this.id,
    required this.userId,
    required this.username,
    required this.body,
    required this.createdAt,
    this.roomId = 'general',
    this.authorRole = 'user',
    this.replyToId,
    this.editedAt,
    this.reactions = const {},
  });

  final int id;
  final String userId;
  final String username;
  final String body;
  final DateTime createdAt;
  final String roomId;
  final String authorRole;
  final int? replyToId;
  final DateTime? editedAt;
  final Map<String, int> reactions;

  bool get isVerified => authorRole == 'owner' || authorRole == 'admin';

  factory PropChatMessage.fromJson(Map<String, dynamic> json) {
    return PropChatMessage(
      id: (json['id'] as num?)?.toInt() ?? 0,
      userId: json['user_id']?.toString() ?? '',
      username: json['username']?.toString() ?? 'member',
      body: json['body']?.toString() ?? '',
      roomId: json['room_id']?.toString() ?? 'general',
      authorRole: json['author_role']?.toString() ?? 'user',
      replyToId: (json['reply_to_id'] as num?)?.toInt(),
      editedAt: DateTime.tryParse(json['edited_at']?.toString() ?? ''),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }

  PropChatMessage withReactions(Map<String, int> value) => PropChatMessage(
    id: id,
    userId: userId,
    username: username,
    body: body,
    createdAt: createdAt,
    roomId: roomId,
    authorRole: authorRole,
    replyToId: replyToId,
    editedAt: editedAt,
    reactions: value,
  );
}

class PropChatReport {
  const PropChatReport({
    required this.id,
    required this.username,
    required this.body,
    required this.reason,
    required this.userId,
  });
  final int id;
  final String username;
  final String body;
  final String reason;
  final String userId;

  factory PropChatReport.fromJson(Map<String, dynamic> json) => PropChatReport(
    id: (json['id'] as num?)?.toInt() ?? 0,
    username: json['message_username']?.toString() ?? 'unknown',
    body: json['message_body']?.toString() ?? '[message unavailable]',
    reason: json['reason']?.toString() ?? 'No reason supplied',
    userId: json['message_user_id']?.toString() ?? '',
  );
}

class PropChatPreferences {
  const PropChatPreferences({
    this.notificationsEnabled = true,
    this.soundsEnabled = true,
  });
  final bool notificationsEnabled;
  final bool soundsEnabled;
}

class PropChatModerationNotice {
  const PropChatModerationNotice({
    required this.id,
    required this.restriction,
    required this.reason,
    this.expiresAt,
  });
  final int id;
  final String restriction;
  final String reason;
  final DateTime? expiresAt;

  factory PropChatModerationNotice.fromJson(Map<String, dynamic> json) =>
      PropChatModerationNotice(
        id: (json['id'] as num?)?.toInt() ?? 0,
        restriction: json['restriction']?.toString() ?? 'warning',
        reason: json['reason']?.toString() ?? 'Community guidelines violation',
        expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? ''),
      );
}

class PropChatNotification {
  const PropChatNotification({
    required this.roomId,
    required this.username,
    required this.body,
  });
  final String roomId;
  final String username;
  final String body;
}

class PropChatOperationalAlert {
  const PropChatOperationalAlert({
    required this.id,
    required this.severity,
    required this.type,
    required this.details,
  });
  final int id;
  final String severity;
  final String type;
  final Map<String, dynamic> details;

  factory PropChatOperationalAlert.fromJson(Map<String, dynamic> json) =>
      PropChatOperationalAlert(
        id: (json['id'] as num?)?.toInt() ?? 0,
        severity: json['severity']?.toString() ?? 'warning',
        type: json['alert_type']?.toString() ?? 'chat_health',
        details: (json['details'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}

class PropChatService {
  static final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);
  static final ValueNotifier<Map<String, int>> unreadByRoom =
      ValueNotifier<Map<String, int>>(const {});
  static final ValueNotifier<PropChatNotification?> latestNotification =
      ValueNotifier<PropChatNotification?>(null);
  static StreamSubscription<List<Map<String, dynamic>>>? _globalMessages;
  static StreamSubscription<AuthState>? _globalAuth;
  static int? _latestObservedMessageId;
  SupabaseClient? get _client => SupabaseService.client;
  String? get currentUserId => _client?.auth.currentUser?.id;

  Future<List<PropChatRoom>> loadRooms() async {
    final client = _client;
    if (client == null) {
      return const [PropChatRoom(id: 'general', name: 'General')];
    }
    final rows = await client
        .from('prop_chat_rooms')
        .select('id, name')
        .eq('is_active', true)
        .order('position');
    return (rows as List)
        .map((row) => PropChatRoom.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  Stream<List<PropChatMessage>> watchMessages({String roomId = 'general'}) {
    final client = _client;
    if (client == null || currentUserId == null) {
      return Stream<List<PropChatMessage>>.value(const []);
    }
    late final StreamController<List<PropChatMessage>> controller;
    StreamSubscription<List<Map<String, dynamic>>>? messages;
    StreamSubscription<List<Map<String, dynamic>>>? reactions;
    var refreshing = false;
    var refreshQueued = false;

    Future<void> refresh() async {
      if (refreshing) {
        refreshQueued = true;
        return;
      }
      refreshing = true;
      try {
        final rows = await client
            .from('prop_chat_messages')
            .select()
            .eq('room_id', roomId)
            .order('created_at')
            .limit(200);
        if (!controller.isClosed) {
          controller.add(
            await _attachReactions((rows as List).cast<Map<String, dynamic>>()),
          );
        }
      } catch (error, stackTrace) {
        if (!controller.isClosed) controller.addError(error, stackTrace);
      } finally {
        refreshing = false;
        if (refreshQueued) {
          refreshQueued = false;
          unawaited(refresh());
        }
      }
    }

    controller = StreamController<List<PropChatMessage>>(
      onListen: () {
        messages = client
            .from('prop_chat_messages')
            .stream(primaryKey: ['id'])
            .eq('room_id', roomId)
            .listen((_) => unawaited(refresh()));
        reactions = client
            .from('prop_chat_reactions')
            .stream(primaryKey: ['message_id', 'user_id', 'emoji'])
            .listen((_) => unawaited(refresh()));
        unawaited(refresh());
      },
      onCancel: () async {
        await messages?.cancel();
        await reactions?.cancel();
      },
    );
    return controller.stream;
  }

  Future<void> startGlobalMonitoring() async {
    final client = _client;
    if (client == null) return;
    _globalAuth ??= client.auth.onAuthStateChange.listen((_) {
      unawaited(_restartGlobalMessageMonitor());
    });
    await _restartGlobalMessageMonitor();
  }

  Future<void> _restartGlobalMessageMonitor() async {
    await _globalMessages?.cancel();
    _globalMessages = null;
    final client = _client;
    if (client == null || currentUserId == null) {
      unreadCount.value = 0;
      unreadByRoom.value = const {};
      return;
    }
    _globalMessages = client
        .from('prop_chat_messages')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .listen((rows) => unawaited(_handleGlobalMessages(rows)));
  }

  Future<void> _handleGlobalMessages(
    List<Map<String, dynamic>> messages,
  ) async {
    await refreshUnreadSummary();
    if (messages.isEmpty) return;
    final latest = PropChatMessage.fromJson(messages.last);
    if (_latestObservedMessageId == null) {
      _latestObservedMessageId = latest.id;
      return;
    }
    if (latest.id <= _latestObservedMessageId! ||
        latest.userId == currentUserId) {
      return;
    }
    _latestObservedMessageId = latest.id;
    final preferences = await loadPreferences();
    if (!preferences.notificationsEnabled) return;
    latestNotification.value = PropChatNotification(
      roomId: latest.roomId,
      username: latest.username,
      body: latest.body,
    );
    if (preferences.soundsEnabled) {
      unawaited(AppSoundService.instance.play(AppSoundEvent.selection));
    }
  }

  Future<void> refreshUnreadSummary() async {
    final client = _client;
    if (client == null || currentUserId == null) return;
    final rows = await client.rpc('prop_chat_unread_summary');
    final values = <String, int>{};
    for (final raw in rows as List) {
      final row = raw as Map<String, dynamic>;
      values[row['room_id']?.toString() ?? 'general'] =
          (row['unread_count'] as num?)?.toInt() ?? 0;
    }
    unreadByRoom.value = values;
    unreadCount.value = values.values.fold(0, (sum, value) => sum + value);
  }

  Future<List<PropChatMessage>> _attachReactions(
    List<Map<String, dynamic>> rows,
  ) async {
    final messages = rows.map(PropChatMessage.fromJson).toList(growable: false);
    if (messages.isEmpty || _client == null) return messages;
    final ids = messages.map((message) => message.id).toList();
    final reactionRows = await _client!
        .from('prop_chat_reactions')
        .select('message_id, emoji')
        .inFilter('message_id', ids);
    final counts = <int, Map<String, int>>{};
    for (final raw in reactionRows as List) {
      final row = raw as Map<String, dynamic>;
      final id = (row['message_id'] as num?)?.toInt();
      final emoji = row['emoji']?.toString();
      if (id == null || emoji == null) continue;
      counts.putIfAbsent(id, () => {})[emoji] = (counts[id]?[emoji] ?? 0) + 1;
    }
    return messages
        .map((message) => message.withReactions(counts[message.id] ?? const {}))
        .toList(growable: false);
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

  Future<void> sendMessage(
    String body, {
    String roomId = 'general',
    int? replyToId,
  }) async {
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
      'room_id': roomId,
      'reply_to_id': replyToId,
    });
  }

  Future<void> editMessage(int messageId, String body) async {
    await _requireClient()
        .from('prop_chat_messages')
        .update({'body': body.trim()})
        .eq('id', messageId);
  }

  Future<void> deleteMessage(int messageId) async {
    await _requireClient()
        .from('prop_chat_messages')
        .delete()
        .eq('id', messageId);
  }

  Future<void> toggleReaction(int messageId, String emoji) async {
    final client = _requireClient();
    final userId = currentUserId!;
    final existing = await client
        .from('prop_chat_reactions')
        .select('message_id')
        .eq('message_id', messageId)
        .eq('user_id', userId)
        .eq('emoji', emoji)
        .maybeSingle();
    if (existing == null) {
      await client.from('prop_chat_reactions').insert({
        'message_id': messageId,
        'user_id': userId,
        'emoji': emoji,
      });
    } else {
      await client
          .from('prop_chat_reactions')
          .delete()
          .eq('message_id', messageId)
          .eq('user_id', userId)
          .eq('emoji', emoji);
    }
  }

  Future<void> reportMessage(int messageId, String reason) async {
    final userId = currentUserId;
    if (userId == null) throw StateError('Sign in to report a message.');
    await _requireClient().from('prop_chat_reports').upsert({
      'message_id': messageId,
      'reporter_id': userId,
      'reason': reason.trim(),
    });
  }

  Future<void> blockUser(String blockedUserId) async {
    final userId = currentUserId;
    if (userId == null) throw StateError('Sign in to block a user.');
    await _requireClient().from('prop_chat_blocks').upsert({
      'blocker_id': userId,
      'blocked_id': blockedUserId,
    });
  }

  Future<String> updateUsername(String username) async {
    final result = await _requireClient().rpc(
      'set_prop_chat_public_username',
      params: {'requested': username},
    );
    return result?.toString() ?? username;
  }

  Future<void> markRoomRead(String roomId) async {
    final userId = currentUserId;
    final client = _client;
    if (userId == null || client == null) return;
    await client.from('prop_chat_read_state').upsert({
      'user_id': userId,
      'room_id': roomId,
      'last_read_at': DateTime.now().toUtc().toIso8601String(),
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'prop_chat_last_read_$roomId',
      DateTime.now().toUtc().toIso8601String(),
    );
    await refreshUnreadSummary();
  }

  Future<DateTime?> localLastRead(String roomId) async {
    final prefs = await SharedPreferences.getInstance();
    return DateTime.tryParse(
      prefs.getString('prop_chat_last_read_$roomId') ?? '',
    );
  }

  Future<PropChatPreferences> loadPreferences() async {
    final userId = currentUserId;
    if (userId == null) return const PropChatPreferences();
    final row = await _requireClient()
        .from('prop_chat_preferences')
        .select('notifications_enabled, sounds_enabled')
        .eq('user_id', userId)
        .maybeSingle();
    return PropChatPreferences(
      notificationsEnabled: row?['notifications_enabled'] as bool? ?? true,
      soundsEnabled: row?['sounds_enabled'] as bool? ?? true,
    );
  }

  Future<void> savePreferences(PropChatPreferences preferences) async {
    final userId = currentUserId;
    if (userId == null) return;
    await _requireClient().from('prop_chat_preferences').upsert({
      'user_id': userId,
      'notifications_enabled': preferences.notificationsEnabled,
      'sounds_enabled': preferences.soundsEnabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> updatePresence(String roomId, {required bool isTyping}) async {
    final userId = currentUserId;
    final client = _client;
    if (userId == null || client == null) return;
    await client.from('prop_chat_presence').upsert({
      'user_id': userId,
      'room_id': roomId,
      'is_typing': isTyping,
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Stream<List<Map<String, dynamic>>> watchPresence(String roomId) {
    final client = _client;
    if (client == null) return Stream.value(const []);
    return client
        .from('prop_chat_presence')
        .stream(primaryKey: ['user_id'])
        .eq('room_id', roomId);
  }

  Stream<List<PropChatModerationNotice>> watchModerationNotices() {
    final client = _client;
    final userId = currentUserId;
    if (client == null || userId == null) return Stream.value(const []);
    return client
        .from('prop_chat_moderation_notices')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .map(
          (rows) => rows
              .where((row) => row['acknowledged_at'] == null)
              .map(PropChatModerationNotice.fromJson)
              .toList(growable: false),
        );
  }

  Future<void> acknowledgeModerationNotice(int noticeId) async {
    await _requireClient().rpc(
      'acknowledge_prop_chat_notice',
      params: {'notice_id': noticeId},
    );
  }

  Future<List<PropChatReport>> loadOpenReports() async {
    final rows = await _requireClient()
        .from('prop_chat_reports')
        .select('id, message_username, message_body, message_user_id, reason')
        .eq('status', 'open')
        .order('created_at');
    return (rows as List)
        .map((row) => PropChatReport.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> loadHealth() async {
    final result = await _requireClient().rpc('prop_chat_health');
    return (result as Map?)?.cast<String, dynamic>() ?? const {};
  }

  Future<List<PropChatOperationalAlert>> loadOperationalAlerts() async {
    final rows = await _requireClient()
        .from('prop_chat_operational_alerts')
        .select('id, severity, alert_type, details')
        .isFilter('resolved_at', null)
        .order('created_at');
    return (rows as List)
        .map(
          (row) =>
              PropChatOperationalAlert.fromJson(row as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  Future<void> resolveOperationalAlert(int alertId) async {
    await _requireClient()
        .from('prop_chat_operational_alerts')
        .update({'resolved_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', alertId);
  }

  Future<void> addBlockedTerm(String term) async {
    await _requireClient().from('prop_chat_blocked_terms').insert({
      'term': term.trim().toLowerCase(),
      'category': 'owner',
    });
  }

  Future<void> resolveReport(int reportId, String status) async {
    await _requireClient()
        .from('prop_chat_reports')
        .update({
          'status': status,
          'reviewed_by': currentUserId,
          'reviewed_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', reportId);
  }

  Future<void> restrictUser(
    String userId,
    String restriction, {
    required String reason,
    DateTime? expiresAt,
  }) async {
    await _requireClient().from('prop_chat_restrictions').upsert({
      'user_id': userId,
      'restriction': restriction,
      'reason': reason,
      'expires_at': expiresAt?.toUtc().toIso8601String(),
      'created_by': currentUserId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  SupabaseClient _requireClient() {
    final client = _client;
    if (client == null || currentUserId == null) {
      throw StateError('PROP CHAT is unavailable.');
    }
    return client;
  }
}
