import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class SportsbookAffiliateRouter {
  static Future<void> routeUserToWagerSlip({
    required String sportsbook,
    required String playerName,
    required String marketType,
  }) async {
    final key = sportsbook.trim().toLowerCase();
    final search = Uri.encodeComponent('$playerName $marketType');

    final Uri uri = switch (key) {
      'draftkings' => Uri.parse('https://sportsbook.draftkings.com/?q=$search'),
      'fanduel' => Uri.parse('https://sportsbook.fanduel.com/?q=$search'),
      _ => Uri.parse('https://www.google.com/search?q=$search+sportsbook'),
    };

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (kDebugMode) {
        debugPrint('Unable to launch affiliate URL: $uri');
      }
    }
  }
}
