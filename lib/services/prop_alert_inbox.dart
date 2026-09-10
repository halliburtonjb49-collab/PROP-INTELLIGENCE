import 'package:flutter/foundation.dart';

/// Shared unread state for the header bell and the alert inbox.
class PropAlertInbox {
  PropAlertInbox._();

  static final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  static void updateUnread(int value) {
    unreadCount.value = value < 0 ? 0 : value;
  }

  static void markRead() => unreadCount.value = 0;
}
