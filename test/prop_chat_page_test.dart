import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/pages/prop_chat_page.dart';
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
  Future<void> sendMessage(
    String body, {
    String roomId = 'general',
    int? replyToId,
    String? attachmentPath,
    String? attachmentKind,
    String? linkUrl,
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
}
