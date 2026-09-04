import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/pages/prop_chat_page.dart';
import 'package:prop_intelligence/services/auth_manager.dart';
import 'package:prop_intelligence/services/prop_chat_service.dart';

class _FakeChatService extends PropChatService {
  _FakeChatService(this.messages);

  final List<PropChatMessage> messages;
  String? sentBody;

  @override
  String? get currentUserId => 'current-user';

  @override
  Stream<List<PropChatMessage>> watchMessages({String roomId = 'general'}) =>
      Stream.value(messages);

  @override
  Future<Set<String>> loadBlockedUserIds() async => const {};

  @override
  Future<List<PropChatConversation>> loadDirectConversations() async => [
    PropChatConversation(
      id: 'conversation-1',
      otherUserId: 'other-user',
      otherUsername: 'line_watcher',
      updatedAt: DateTime(2026, 7, 25, 12),
      unreadCount: 2,
    ),
  ];

  @override
  Stream<List<PropChatMessage>> watchDirectMessages(String conversationId) =>
      Stream.value(messages);

  @override
  Future<void> markDirectConversationRead(String conversationId) async {}

  @override
  Future<void> sendMessage(
    String body, {
    String roomId = 'general',
    int? replyToId,
    String? attachmentPath,
    String? attachmentKind,
    String? linkUrl,
    Map<String, dynamic>? sharedPayload,
  }) async {
    sentBody = body;
  }
}

void main() {
  test('chat messages parse without any email field', () {
    final message = PropChatMessage.fromJson({
      'id': 8,
      'user_id': 'user-1',
      'username': 'prop_captain',
      'body': 'Good line movement.',
      'room_id': 'wnba',
      'author_role': 'admin',
      'created_at': '2026-07-25T12:00:00Z',
      'email': 'private@example.com',
    });

    expect(message.username, 'prop_captain');
    expect(message.body, 'Good line movement.');
    expect(message.roomId, 'wnba');
    expect(message.isVerified, isTrue);
  });

  test('numbered founder identity is parsed from trusted chat fields', () {
    final message = PropChatMessage.fromJson({
      'id': 11,
      'user_id': 'founder-user',
      'username': 'founder_member',
      'body': 'Founder note.',
      'author_role': 'pro_founder',
      'author_badge_number': 7,
      'created_at': '2026-08-10T12:00:00Z',
    });

    expect(message.normalizedAuthorRole, 'pro_founder');
    expect(message.authorBadgeNumber, 7);
  });
  test('owner role is normalized and marked as official', () {
    final message = PropChatMessage.fromJson({
      'id': 10,
      'user_id': 'owner-user',
      'username': 'prop_owner',
      'body': 'Official update.',
      'author_role': ' OWNER ',
      'created_at': '2026-07-25T12:00:00Z',
    });

    expect(message.isOfficialOwner, isTrue);
    expect(message.isVerified, isTrue);
  });

  test('current owner identity corrects older chat rows saved as user', () {
    final message = PropChatMessage.fromJson({
      'id': 12,
      'user_id': 'owner-user',
      'username': 'prop_owner',
      'body': 'Older owner message.',
      'author_role': 'user',
      'created_at': '2026-08-10T12:00:00Z',
    });
    const session = AuthSessionState(
      ready: true,
      authenticated: true,
      isPremium: true,
      subscriptionTier: SubscriptionTier.edge,
      role: 'owner',
      userId: 'owner-user',
      email: 'owner@example.com',
      username: 'prop_owner',
      message: 'Authenticated',
    );

    final corrected = resolveCurrentUserMessageIdentity(message, session);

    expect(corrected.normalizedAuthorRole, 'owner');
    expect(corrected.isOfficialOwner, isTrue);
  });

  test('protected owner announcements survive a legacy user role', () {
    final message = PropChatMessage.fromJson({
      'id': 13,
      'user_id': 'owner-user',
      'username': 'prop_owner',
      'body': '[PI ANNOUNCEMENT]\nTonight’s slate is live.',
      'room_id': 'general',
      'author_role': 'user',
      'created_at': '2026-09-04T12:00:00Z',
    });

    final corrected = resolveAnnouncementIdentity(message);

    expect(corrected.isAnnouncement, isTrue);
    expect(corrected.displayBody, 'Tonight’s slate is live.');
    expect(corrected.normalizedAuthorRole, 'owner');
  });

  test(
    'Discord messages are identified as external and not verified staff',
    () {
      final message = PropChatMessage.fromJson({
        'id': -1,
        'user_id': 'discord:123',
        'username': 'discord_member',
        'body': 'Message from the community server.',
        'author_role': 'discord',
        'created_at': '2026-08-10T12:00:00Z',
      });

      expect(message.isDiscord, isTrue);
      expect(message.isVerified, isFalse);
      expect(message.isOfficialOwner, isFalse);
    },
  );

  test('chat messages parse secure attachments and HTTPS links', () {
    final message = PropChatMessage.fromJson({
      'id': 9,
      'user_id': 'user-1',
      'username': 'ticket_reader',
      'body': 'Ticket from tonight.',
      'attachment_path': 'user-1/example.png',
      'attachment_kind': 'ticket',
      'link_url': 'https://example.com/card',
      'created_at': '2026-07-25T12:00:00Z',
    });

    expect(message.attachmentKind, 'ticket');
    expect(message.attachmentPath, 'user-1/example.png');
    expect(message.linkUrl, 'https://example.com/card');
  });

  test('direct conversation summaries parse privacy-safe member data', () {
    final conversation = PropChatConversation.fromJson({
      'conversation_id': 'conversation-1',
      'other_user_id': 'user-2',
      'other_username': 'line_reader',
      'updated_at': '2026-07-25T12:00:00Z',
      'unread_count': 3,
    });

    expect(conversation.otherUsername, 'line_reader');
    expect(conversation.unreadCount, 3);
  });

  testWidgets('PROP CHAT renders usernames and sends text', (tester) async {
    final service = _FakeChatService([
      PropChatMessage(
        id: 1,
        userId: 'other-user',
        username: 'line_watcher',
        body: 'WNBA total just moved.',
        createdAt: DateTime(2026, 7, 25, 12),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: PropChatPage(service: service)),
      ),
    );
    await tester.pump();

    expect(find.text('PROP CHAT'), findsOneWidget);
    expect(find.text('GENERAL'), findsOneWidget);
    expect(find.text('@line_watcher'), findsOneWidget);
    expect(find.text('WNBA total just moved.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('prop-chat-message-field')),
      'I see it.',
    );
    await tester.tap(find.byKey(const ValueKey('prop-chat-send-button')));
    await tester.pump();

    expect(service.sentBody, 'I see it.');
  });

  testWidgets('PROP CHAT identifies official owner messages in gold', (
    tester,
  ) async {
    final service = _FakeChatService([
      PropChatMessage(
        id: 2,
        userId: 'owner-user',
        username: 'prop_owner',
        body: 'Official board update.',
        authorRole: 'owner',
        createdAt: DateTime(2026, 7, 25, 12),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: PropChatPage(service: service)),
      ),
    );
    await tester.pump();

    expect(find.text('@prop_owner'), findsOneWidget);
    expect(find.text('OWNER'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('member-identity-prop_owner')),
      findsOneWidget,
    );
  });

  testWidgets('PROP CHAT direct messages use a mobile master-detail flow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final service = _FakeChatService([
      PropChatMessage(
        id: 1,
        userId: 'other-user',
        username: 'line_watcher',
        body: 'Mobile DM is visible.',
        createdAt: DateTime(2026, 7, 25, 12),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: PropChatPage(service: service)),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('prop-chat-direct-messages')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile-direct-conversation-list')),
      findsOneWidget,
    );
    expect(find.text('@line_watcher'), findsWidgets);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('mobile-direct-conversation-list')),
        matching: find.text('@line_watcher'),
      ),
    );
    await tester.pumpAndSettle();
    final mobileDialog = find.byKey(
      const ValueKey('mobile-direct-messages-dialog'),
    );
    expect(
      find.descendant(
        of: mobileDialog,
        matching: find.text('Mobile DM is visible.'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-direct-message-back')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: mobileDialog,
        matching: find.byKey(const ValueKey('prop-chat-message-field')),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('mobile-direct-message-back')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile-direct-conversation-list')),
      findsOneWidget,
    );
  });
}
