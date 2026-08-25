import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api_service.dart';
import 'auth_manager.dart';
import 'live_update_service.dart';
import 'supabase_service.dart';
import 'app_sound_service.dart';

class PropChatRoom {
  const PropChatRoom({
    required this.id,
    required this.name,
    this.roomType = 'sport',
    this.sport,
    this.eventId,
    this.requiredTier = 'edge',
  });
  final String id;
  final String name;
  final String roomType;
  final String? sport;
  final String? eventId;
  final String requiredTier;
  bool get isGame => roomType == 'game';
  bool get isPro => requiredTier == 'edge';

  factory PropChatRoom.fromJson(Map<String, dynamic> json) => PropChatRoom(
    id: json['id']?.toString() ?? 'general',
    name: json['name']?.toString() ?? 'General',
    roomType: json['room_type']?.toString() ?? 'sport',
    sport: json['sport']?.toString(),
    eventId: json['event_id']?.toString(),
    requiredTier: json['required_tier']?.toString() ?? 'edge',
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
    this.authorBadgeNumber,
    this.replyToId,
    this.editedAt,
    this.reactions = const {},
    this.attachmentPath,
    this.attachmentKind,
    this.linkUrl,
    this.attachmentUrl,
    this.sharedPayload,
  });

  final int id;
  final String userId;
  final String username;
  final String body;
  final DateTime createdAt;
  final String roomId;
  final String authorRole;
  final int? authorBadgeNumber;
  final int? replyToId;
  final DateTime? editedAt;
  final Map<String, int> reactions;
  final String? attachmentPath;
  final String? attachmentKind;
  final String? linkUrl;
  final String? attachmentUrl;
  final Map<String, dynamic>? sharedPayload;

  String get normalizedAuthorRole => authorRole.trim().toLowerCase();
  bool get isOfficialOwner => normalizedAuthorRole == 'owner';
  bool get isDiscord => normalizedAuthorRole == 'discord';
  bool get isVerified => const {
    'owner',
    'admin',
    'expert',
    'creator',
  }.contains(normalizedAuthorRole);

  factory PropChatMessage.fromJson(Map<String, dynamic> json) {
    return PropChatMessage(
      id: (json['id'] as num?)?.toInt() ?? 0,
      userId: json['user_id']?.toString() ?? '',
      username: json['username']?.toString() ?? 'member',
      body: json['body']?.toString() ?? '',
      roomId: json['room_id']?.toString() ?? 'general',
      authorRole: json['author_role']?.toString() ?? 'user',
      authorBadgeNumber: (json['author_badge_number'] as num?)?.toInt(),
      replyToId: (json['reply_to_id'] as num?)?.toInt(),
      editedAt: DateTime.tryParse(json['edited_at']?.toString() ?? ''),
      attachmentPath: json['attachment_path']?.toString(),
      attachmentKind: json['attachment_kind']?.toString(),
      linkUrl: json['link_url']?.toString(),
      sharedPayload: (json['shared_payload'] as Map?)?.cast<String, dynamic>(),
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
    authorBadgeNumber: authorBadgeNumber,
    replyToId: replyToId,
    editedAt: editedAt,
    reactions: value,
    attachmentPath: attachmentPath,
    attachmentKind: attachmentKind,
    linkUrl: linkUrl,
    attachmentUrl: attachmentUrl,
    sharedPayload: sharedPayload,
  );

  PropChatMessage withAttachmentUrl(String? value) => PropChatMessage(
    id: id,
    userId: userId,
    username: username,
    body: body,
    createdAt: createdAt,
    roomId: roomId,
    authorRole: authorRole,
    authorBadgeNumber: authorBadgeNumber,
    replyToId: replyToId,
    editedAt: editedAt,
    reactions: reactions,
    attachmentPath: attachmentPath,
    attachmentKind: attachmentKind,
    linkUrl: linkUrl,
    attachmentUrl: value,
    sharedPayload: sharedPayload,
  );

  PropChatMessage withAuthorIdentity({
    required String role,
    int? badgeNumber,
  }) => PropChatMessage(
    id: id,
    userId: userId,
    username: username,
    body: body,
    createdAt: createdAt,
    roomId: roomId,
    authorRole: role,
    authorBadgeNumber: badgeNumber,
    replyToId: replyToId,
    editedAt: editedAt,
    reactions: reactions,
    attachmentPath: attachmentPath,
    attachmentKind: attachmentKind,
    linkUrl: linkUrl,
    attachmentUrl: attachmentUrl,
    sharedPayload: sharedPayload,
  );
}

PropChatMessage resolveCurrentUserMessageIdentity(
  PropChatMessage message,
  AuthSessionState session,
) {
  if (!session.authenticated ||
      session.userId == null ||
      message.userId != session.userId) {
    return message;
  }
  final accountRole = session.role.trim().toLowerCase();
  final assignedRole = session.assignedMemberRole?.trim().toLowerCase();
  final role = switch (accountRole) {
    'owner' || 'admin' => accountRole,
    _ when const {'core', 'pro', 'pro_founder'}.contains(assignedRole) =>
      assignedRole!,
    _ when session.effectiveSubscriptionTier == SubscriptionTier.edge => 'pro',
    _ when session.effectiveSubscriptionTier == SubscriptionTier.core => 'core',
    _ => message.authorRole,
  };
  final badgeNumber = role == 'pro_founder'
      ? session.founderNumber
      : message.authorBadgeNumber;
  return message.withAuthorIdentity(role: role, badgeNumber: badgeNumber);
}

class PropChatMember {
  const PropChatMember({required this.userId, required this.username});
  final String userId;
  final String username;
}

class PropChatConversation {
  const PropChatConversation({
    required this.id,
    required this.otherUserId,
    required this.otherUsername,
    required this.updatedAt,
    required this.unreadCount,
  });
  final String id;
  final String otherUserId;
  final String otherUsername;
  final DateTime updatedAt;
  final int unreadCount;

  factory PropChatConversation.fromJson(Map<String, dynamic> json) =>
      PropChatConversation(
        id: json['conversation_id']?.toString() ?? '',
        otherUserId: json['other_user_id']?.toString() ?? '',
        otherUsername: json['other_username']?.toString() ?? 'member',
        updatedAt:
            DateTime.tryParse(
              json['updated_at']?.toString() ?? '',
            )?.toLocal() ??
            DateTime.now(),
        unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      );
}

class PropChatReport {
  const PropChatReport({
    required this.id,
    required this.username,
    required this.body,
    required this.reason,
    required this.userId,
    this.isDirect = false,
  });
  final int id;
  final String username;
  final String body;
  final String reason;
  final String userId;
  final bool isDirect;

  factory PropChatReport.fromJson(
    Map<String, dynamic> json, {
    bool isDirect = false,
  }) => PropChatReport(
    id: (json['id'] as num?)?.toInt() ?? 0,
    username: json['message_username']?.toString() ?? 'unknown',
    body: json['message_body']?.toString() ?? '[message unavailable]',
    reason: json['reason']?.toString() ?? 'No reason supplied',
    userId: json['message_user_id']?.toString() ?? '',
    isDirect: isDirect,
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
    this.isDirect = false,
  });
  final String roomId;
  final String username;
  final String body;
  final bool isDirect;
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
  static const List<PropChatRoom> _standardRooms = [
    PropChatRoom(
      id: 'general',
      name: 'General',
      roomType: 'general',
      requiredTier: 'core',
    ),
    PropChatRoom(id: 'mlb', name: 'MLB', sport: 'MLB', requiredTier: 'core'),
    PropChatRoom(id: 'nfl', name: 'NFL', sport: 'NFL', requiredTier: 'core'),
    PropChatRoom(id: 'nba', name: 'NBA', sport: 'NBA', requiredTier: 'core'),
    PropChatRoom(id: 'wnba', name: 'WNBA', sport: 'WNBA', requiredTier: 'core'),
    PropChatRoom(id: 'nhl', name: 'NHL', sport: 'NHL', requiredTier: 'core'),
    PropChatRoom(
      id: 'soccer',
      name: 'Soccer',
      sport: 'SOCCER',
      requiredTier: 'core',
    ),
    PropChatRoom(
      id: 'ncaaf',
      name: 'NCAAF',
      sport: 'NCAAF',
      requiredTier: 'core',
    ),
    PropChatRoom(
      id: 'ncaab',
      name: 'NCAAB',
      sport: 'NCAAB',
      requiredTier: 'core',
    ),
    PropChatRoom(id: 'cfl', name: 'CFL', sport: 'CFL', requiredTier: 'core'),
  ];
  static final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);
  static final ValueNotifier<Map<String, int>> unreadByRoom =
      ValueNotifier<Map<String, int>>(const {});
  static final ValueNotifier<PropChatNotification?> latestNotification =
      ValueNotifier<PropChatNotification?>(null);
  static StreamSubscription<List<Map<String, dynamic>>>? _globalMessages;
  static StreamSubscription<List<Map<String, dynamic>>>? _globalDirectMessages;
  static StreamSubscription<AuthState>? _globalAuth;
  static int? _latestObservedMessageId;
  static int? _latestObservedDirectMessageId;
  SupabaseClient? get _client => SupabaseService.client;
  String? get currentUserId => _client?.auth.currentUser?.id;

  Future<List<PropChatRoom>> loadRooms() async {
    final client = _client;
    if (client == null) {
      return _standardRooms;
    }
    try {
      final rows = await client
          .from('prop_chat_rooms')
          .select('id, name, room_type, sport, event_id, required_tier')
          .eq('is_active', true)
          .order('position');
      final liveRooms = (rows as List)
          .map((row) => PropChatRoom.fromJson(row as Map<String, dynamic>))
          .toList(growable: false);
      final liveById = {for (final room in liveRooms) room.id: room};
      return [
        for (final room in _standardRooms) liveById.remove(room.id) ?? room,
        ...liveById.values,
      ];
    } catch (error) {
      debugPrint('PROP CHAT rooms unavailable; using standard rooms: $error');
      return _standardRooms;
    }
  }

  Stream<List<PropChatMessage>> watchMessages({String roomId = 'general'}) {
    final client = _client;
    if (client == null) {
      return Stream<List<PropChatMessage>>.value(const []);
    }
    late final StreamController<List<PropChatMessage>> controller;
    StreamSubscription<List<Map<String, dynamic>>>? messages;
    StreamSubscription<List<Map<String, dynamic>>>? reactions;
    StreamSubscription<AuthState>? authChanges;
    LiveUpdateService? discordUpdates;
    StreamSubscription<dynamic>? discordEvents;
    Timer? refreshRetry;
    Timer? pollingRefresh;
    List<PropChatMessage> storedMessages = const [];
    final externalMessages = <String, PropChatMessage>{};
    var refreshing = false;
    var refreshQueued = false;
    var refreshAttempts = 0;
    var realtimeAttached = false;

    void emitMessages() {
      if (controller.isClosed) return;
      final combined = <PropChatMessage>[
        ...storedMessages,
        ...externalMessages.values,
      ]..sort((left, right) => left.createdAt.compareTo(right.createdAt));
      controller.add(combined);
    }

    void handleDiscordEvent(dynamic rawEvent) {
      try {
        final decoded = rawEvent is String ? jsonDecode(rawEvent) : rawEvent;
        if (decoded is! Map || decoded['type'] != 'chat.discord.message') {
          return;
        }
        final event = Map<String, dynamic>.from(decoded);
        final rawData = event['data'];
        if (rawData is! Map) return;
        final data = Map<String, dynamic>.from(rawData);
        if (data['roomId']?.toString() != roomId) return;
        final externalId =
            data['id']?.toString() ?? event['eventId']?.toString();
        if (externalId == null || externalId.isEmpty) return;
        final numericId =
            BigInt.tryParse(externalId) ??
            BigInt.from(externalId.hashCode.abs());
        final boundedId = (numericId % BigInt.from(0x7fffffff)).toInt();
        externalMessages[externalId] = PropChatMessage(
          id: -(boundedId + 1),
          userId: data['userId']?.toString() ?? 'discord',
          username: data['username']?.toString() ?? 'discord_member',
          body: data['body']?.toString() ?? '',
          createdAt:
              DateTime.tryParse(
                event['occurredAt']?.toString() ?? '',
              )?.toLocal() ??
              DateTime.now(),
          roomId: roomId,
          authorRole: 'discord',
        );
        while (externalMessages.length > 100) {
          externalMessages.remove(externalMessages.keys.first);
        }
        emitMessages();
      } catch (_) {
        // Supabase chat remains available if a malformed bridge event arrives.
      }
    }

    Future<void> refresh() async {
      if (currentUserId == null) return;
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
        storedMessages = await _attachReactions(
          (rows as List).cast<Map<String, dynamic>>(),
        );
        refreshRetry?.cancel();
        refreshRetry = null;
        refreshAttempts = 0;
        emitMessages();
      } catch (error, stackTrace) {
        debugPrint('PROP CHAT message refresh unavailable: $error');
        if (!controller.isClosed && refreshRetry == null) {
          final exponent = refreshAttempts > 4 ? 4 : refreshAttempts;
          final delay = Duration(seconds: 1 << exponent);
          refreshAttempts++;
          refreshRetry = Timer(delay, () {
            refreshRetry = null;
            if (!controller.isClosed) unawaited(refresh());
          });
        }
      } finally {
        refreshing = false;
        if (refreshQueued) {
          refreshQueued = false;
          unawaited(refresh());
        }
      }
    }

    Future<void> attachAuthenticatedStreams() async {
      if (controller.isClosed || currentUserId == null) return;
      if (!realtimeAttached) {
        realtimeAttached = true;
        messages = client
            .from('prop_chat_messages')
            .stream(primaryKey: ['id'])
            .eq('room_id', roomId)
            .listen(
              (_) => unawaited(refresh()),
              onError: (error, _) {
                debugPrint('PROP CHAT message realtime unavailable: $error');
                unawaited(refresh());
              },
            );
        reactions = client
            .from('prop_chat_reactions')
            .stream(primaryKey: ['message_id', 'user_id', 'emoji'])
            .listen(
              (_) => unawaited(refresh()),
              onError: (error, _) {
                debugPrint('PROP CHAT reaction realtime unavailable: $error');
                unawaited(refresh());
              },
            );
      }
      await refresh();
    }

    controller = StreamController<List<PropChatMessage>>(
      onListen: () {
        authChanges = client.auth.onAuthStateChange.listen((event) {
          if (event.session == null) {
            realtimeAttached = false;
            final activeMessages = messages;
            final activeReactions = reactions;
            if (activeMessages != null) unawaited(activeMessages.cancel());
            if (activeReactions != null) unawaited(activeReactions.cancel());
            messages = null;
            reactions = null;
            if (!controller.isClosed) controller.add(const []);
            return;
          }
          unawaited(attachAuthenticatedStreams());
        });
        if (roomId == 'general') {
          discordUpdates = LiveUpdateService(channels: const {'chat'});
          discordEvents = discordUpdates!.stream.listen(
            handleDiscordEvent,
            onError: (_) {},
          );
          discordUpdates!.connect();
        }
        // Realtime delivery is an enhancement, not a single point of failure.
        // Polling keeps chat usable when a proxy, mobile network, or Supabase
        // websocket briefly drops without creating duplicate subscriptions.
        pollingRefresh = Timer.periodic(
          const Duration(seconds: 12),
          (_) => unawaited(refresh()),
        );
        emitMessages();
        unawaited(attachAuthenticatedStreams());
      },
      onCancel: () async {
        refreshRetry?.cancel();
        pollingRefresh?.cancel();
        await messages?.cancel();
        await reactions?.cancel();
        await authChanges?.cancel();
        await discordEvents?.cancel();
        await discordUpdates?.dispose();
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
    await _globalDirectMessages?.cancel();
    _globalMessages = null;
    _globalDirectMessages = null;
    _latestObservedMessageId = null;
    _latestObservedDirectMessageId = null;
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
    _globalDirectMessages = client
        .from('prop_chat_direct_messages')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .listen((rows) => unawaited(_handleGlobalDirectMessages(rows)));
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
    final username = AuthManager.instance.sessionState.value.username?.trim();
    if (username == null ||
        username.isEmpty ||
        !_containsMention(latest.body, username)) {
      return;
    }
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

  Future<void> _handleGlobalDirectMessages(
    List<Map<String, dynamic>> messages,
  ) async {
    await refreshUnreadSummary();
    if (messages.isEmpty) return;
    final latest = PropChatMessage.fromJson(messages.last);
    if (_latestObservedDirectMessageId == null) {
      _latestObservedDirectMessageId = latest.id;
      return;
    }
    if (latest.id <= _latestObservedDirectMessageId! ||
        latest.userId == currentUserId) {
      return;
    }
    _latestObservedDirectMessageId = latest.id;
    final preferences = await loadPreferences();
    if (!preferences.notificationsEnabled) return;
    latestNotification.value = PropChatNotification(
      roomId: latest.roomId,
      username: latest.username,
      body: latest.body,
      isDirect: true,
    );
    if (preferences.soundsEnabled) {
      unawaited(AppSoundService.instance.play(AppSoundEvent.selection));
    }
  }

  static bool _containsMention(String body, String username) {
    final escaped = RegExp.escape(username);
    return RegExp(
      '(^|[^a-zA-Z0-9_])@$escaped([^a-zA-Z0-9_]|\$)',
      caseSensitive: false,
    ).hasMatch(body);
  }

  Future<void> refreshUnreadSummary() async {
    final client = _client;
    if (client == null || currentUserId == null) return;
    final rows = await client.rpc('prop_chat_notification_summary');
    final values = <String, int>{};
    for (final raw in rows as List) {
      final row = raw as Map<String, dynamic>;
      final type = row['notification_type']?.toString() ?? 'mention';
      final source = row['source_id']?.toString() ?? 'general';
      values['$type:$source'] = (row['unread_count'] as num?)?.toInt() ?? 0;
    }
    unreadByRoom.value = values;
    unreadCount.value = values.values.fold(0, (sum, value) => sum + value);
  }

  Future<List<PropChatMessage>> _attachReactions(
    List<Map<String, dynamic>> rows,
  ) async {
    final session = AuthManager.instance.sessionState.value;
    final messages = rows
        .map(PropChatMessage.fromJson)
        .map((message) => resolveCurrentUserMessageIdentity(message, session))
        .toList(growable: false);
    if (messages.isEmpty || _client == null) return messages;
    final ids = messages.map((message) => message.id).toList();
    dynamic reactionRows;
    try {
      reactionRows = await _client!
          .from('prop_chat_reactions')
          .select('message_id, emoji')
          .inFilter('message_id', ids);
    } catch (error) {
      // Reactions are optional enrichment. A missing migration, temporary RLS
      // failure, or realtime outage must never hide otherwise valid messages.
      debugPrint('PROP CHAT reactions unavailable: $error');
      return _attachSignedUrls(messages);
    }
    final counts = <int, Map<String, int>>{};
    for (final raw in reactionRows as List) {
      final row = raw as Map<String, dynamic>;
      final id = (row['message_id'] as num?)?.toInt();
      final emoji = row['emoji']?.toString();
      if (id == null || emoji == null) continue;
      counts.putIfAbsent(id, () => {})[emoji] = (counts[id]?[emoji] ?? 0) + 1;
    }
    final withReactions = messages
        .map((message) => message.withReactions(counts[message.id] ?? const {}))
        .toList(growable: false);
    return _attachSignedUrls(withReactions);
  }

  Future<List<PropChatMessage>> _attachSignedUrls(
    List<PropChatMessage> messages,
  ) async {
    final client = _client;
    if (client == null) return messages;
    return Future.wait(
      messages.map((message) async {
        final path = message.attachmentPath;
        if (path == null || path.isEmpty) return message;
        try {
          final url = await client.storage
              .from('prop-chat-private')
              .createSignedUrl(path, 600);
          return message.withAttachmentUrl(url);
        } catch (_) {
          return message;
        }
      }),
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

  Future<void> sendMessage(
    String body, {
    String roomId = 'general',
    int? replyToId,
    String? attachmentPath,
    String? attachmentKind,
    String? linkUrl,
    Map<String, dynamic>? sharedPayload,
  }) async {
    final client = _client;
    final userId = currentUserId;
    final trimmed = body.trim();
    if (client == null || userId == null) {
      throw StateError('Sign in to use PROP CHAT.');
    }
    if ((trimmed.isEmpty && attachmentPath == null && sharedPayload == null) ||
        trimmed.length > 500) {
      throw ArgumentError('Messages must contain 1–500 characters.');
    }
    await client.from('prop_chat_messages').insert({
      'user_id': userId,
      'username': 'server-assigned',
      'body': trimmed,
      'room_id': roomId,
      'reply_to_id': replyToId,
      'attachment_path': attachmentPath,
      'attachment_kind': attachmentKind,
      'link_url': linkUrl,
      'shared_payload': sharedPayload,
    });
    if (roomId == 'general' && trimmed.isNotEmpty) {
      unawaited(ApiService().mirrorPropChatToDiscord(trimmed));
    }
  }

  Future<String> createGameThread({
    required String eventId,
    required String sport,
    required String name,
  }) async {
    final result = await _requireClient().rpc(
      'create_prop_chat_game_thread',
      params: {
        'game_event_id': eventId,
        'game_sport': sport,
        'game_name': name,
      },
    );
    return result.toString();
  }

  Future<void> registerPushSubscription({
    required String deviceKey,
    required String platform,
    required String endpoint,
  }) async {
    final userId = currentUserId;
    if (userId == null) throw StateError('Sign in to enable notifications.');
    await _requireClient().from('prop_chat_push_subscriptions').upsert({
      'user_id': userId,
      'device_key': deviceKey,
      'platform': platform,
      'endpoint': endpoint,
      'active': true,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,device_key');
  }

  Future<String> uploadChatImage(
    Uint8List bytes, {
    required String extension,
    required String contentType,
  }) async {
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw ArgumentError('Images must be between 1 byte and 5 MB.');
    }
    const allowed = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
    };
    final normalized = extension.toLowerCase();
    if (allowed[normalized] != contentType ||
        !allowed.containsKey(normalized)) {
      throw ArgumentError('Only JPG, PNG, and WebP images are allowed.');
    }
    final userId = currentUserId;
    if (userId == null) throw StateError('Sign in to upload an image.');
    final random = Random.secure();
    String hex(int count) => List.generate(
      count,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    final id =
        '${hex(8)}-${hex(4)}-4${hex(3)}-'
        '${(8 + random.nextInt(4)).toRadixString(16)}${hex(3)}-${hex(12)}';
    final path = '$userId/$id.$normalized';
    await _requireClient().storage
        .from('prop-chat-private')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    return path;
  }

  Future<List<PropChatMember>> findMembers(String query) async {
    final value = query.trim();
    if (value.length < 2) return const [];
    final rows = await _requireClient().rpc(
      'find_prop_chat_members',
      params: {'query': value},
    );
    return (rows as List)
        .map(
          (row) => PropChatMember(
            userId: (row as Map<String, dynamic>)['user_id'].toString(),
            username: row['username'].toString(),
          ),
        )
        .toList(growable: false);
  }

  Future<String> startDirectConversation(String otherUserId) async {
    final result = await _requireClient().rpc(
      'start_prop_chat_direct_conversation',
      params: {'other_user': otherUserId},
    );
    return result.toString();
  }

  Future<List<PropChatConversation>> loadDirectConversations() async {
    final rows = await _requireClient().rpc('prop_chat_direct_conversations');
    return (rows as List)
        .map(
          (row) => PropChatConversation.fromJson(row as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  Stream<List<PropChatMessage>> watchDirectMessages(String conversationId) {
    final client = _client;
    if (client == null || currentUserId == null) {
      return Stream.value(const []);
    }
    return client
        .from('prop_chat_direct_messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at')
        .asyncMap((rows) {
          final session = AuthManager.instance.sessionState.value;
          return _attachSignedUrls(
            rows
                .map(PropChatMessage.fromJson)
                .map(
                  (message) =>
                      resolveCurrentUserMessageIdentity(message, session),
                )
                .toList(growable: false),
          );
        });
  }

  Future<void> sendDirectMessage(
    String conversationId,
    String body, {
    String? attachmentPath,
    String? attachmentKind,
    String? linkUrl,
  }) async {
    final userId = currentUserId;
    if (userId == null) throw StateError('Sign in to send a message.');
    final trimmed = body.trim();
    if ((trimmed.isEmpty && attachmentPath == null) || trimmed.length > 500) {
      throw ArgumentError('Messages must contain text or an image.');
    }
    await _requireClient().from('prop_chat_direct_messages').insert({
      'conversation_id': conversationId,
      'user_id': userId,
      'username': 'server-assigned',
      'body': trimmed,
      'attachment_path': attachmentPath,
      'attachment_kind': attachmentKind,
      'link_url': linkUrl,
    });
  }

  Future<void> reportDirectMessage(int messageId, String reason) async {
    final userId = currentUserId;
    if (userId == null) throw StateError('Sign in to report a message.');
    await _requireClient().from('prop_chat_direct_reports').upsert({
      'message_id': messageId,
      'reporter_id': userId,
      'reason': reason.trim(),
    });
  }

  Future<void> markDirectConversationRead(String conversationId) async {
    await _requireClient()
        .from('prop_chat_conversation_members')
        .update({'last_read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('conversation_id', conversationId)
        .eq('user_id', currentUserId!);
    await refreshUnreadSummary();
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
    try {
      await client.from('prop_chat_presence').upsert({
        'user_id': userId,
        'room_id': roomId,
        'is_typing': isTyping,
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (error) {
      // Presence must never interrupt messages or surface an unhandled async
      // error when the presence table/realtime channel is temporarily down.
      debugPrint('PROP CHAT presence update unavailable: $error');
    }
  }

  Stream<List<Map<String, dynamic>>> watchPresence(String roomId) {
    final client = _client;
    if (client == null) return Stream.value(const []);
    late final StreamController<List<Map<String, dynamic>>> controller;
    StreamSubscription<List<Map<String, dynamic>>>? realtime;
    Timer? polling;

    Future<void> refresh() async {
      if (controller.isClosed) return;
      try {
        final rows = await client
            .from('prop_chat_presence')
            .select('user_id, room_id, is_typing, last_seen_at')
            .eq('room_id', roomId)
            .gte(
              'last_seen_at',
              DateTime.now()
                  .toUtc()
                  .subtract(const Duration(minutes: 2))
                  .toIso8601String(),
            );
        if (!controller.isClosed) {
          controller.add((rows as List).cast<Map<String, dynamic>>());
        }
      } catch (error) {
        debugPrint('PROP CHAT presence unavailable: $error');
        if (!controller.isClosed) controller.add(const []);
      }
    }

    controller = StreamController<List<Map<String, dynamic>>>(
      onListen: () {
        realtime = client
            .from('prop_chat_presence')
            .stream(primaryKey: ['user_id'])
            .eq('room_id', roomId)
            .listen(
              (_) => unawaited(refresh()),
              onError: (_, _) => unawaited(refresh()),
            );
        polling = Timer.periodic(
          const Duration(seconds: 20),
          (_) => unawaited(refresh()),
        );
        unawaited(refresh());
      },
      onCancel: () async {
        polling?.cancel();
        await realtime?.cancel();
      },
    );
    return controller.stream;
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
    final client = _requireClient();
    final values = await Future.wait([
      client
          .from('prop_chat_reports')
          .select('id, message_username, message_body, message_user_id, reason')
          .eq('status', 'open')
          .order('created_at'),
      client
          .from('prop_chat_direct_reports')
          .select('id, message_username, message_body, message_user_id, reason')
          .eq('status', 'open')
          .order('created_at'),
    ]);
    return [
      for (final row in values[0] as List)
        PropChatReport.fromJson(row as Map<String, dynamic>),
      for (final row in values[1] as List)
        PropChatReport.fromJson(row as Map<String, dynamic>, isDirect: true),
    ];
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

  Future<void> resolveReport(
    int reportId,
    String status, {
    bool isDirect = false,
  }) async {
    await _requireClient()
        .from(isDirect ? 'prop_chat_direct_reports' : 'prop_chat_reports')
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
