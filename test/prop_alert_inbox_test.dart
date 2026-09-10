import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/services/prop_alert_inbox.dart';

void main() {
  tearDown(PropAlertInbox.markRead);

  test('unread count reflects real inbox state and clears on read', () {
    PropAlertInbox.updateUnread(3);
    expect(PropAlertInbox.unreadCount.value, 3);

    PropAlertInbox.markRead();
    expect(PropAlertInbox.unreadCount.value, 0);
  });

  test('unread count never becomes negative', () {
    PropAlertInbox.updateUnread(-1);
    expect(PropAlertInbox.unreadCount.value, 0);
  });
}
