import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class InjuryAlertPreferences {
  const InjuryAlertPreferences({
    this.enabled = true,
    this.criticalOnly = false,
  });

  static const enabledKey = 'injury_alerts_enabled';
  static const criticalOnlyKey = 'injury_alerts_critical_only';

  final bool enabled;
  final bool criticalOnly;

  static Future<InjuryAlertPreferences> load() async {
    final preferences = await SharedPreferences.getInstance();
    return InjuryAlertPreferences(
      enabled: preferences.getBool(enabledKey) ?? true,
      criticalOnly: preferences.getBool(criticalOnlyKey) ?? false,
    );
  }

  Future<void> save() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(enabledKey, enabled);
    await preferences.setBool(criticalOnlyKey, criticalOnly);
  }

  InjuryAlertPreferences copyWith({bool? enabled, bool? criticalOnly}) =>
      InjuryAlertPreferences(
        enabled: enabled ?? this.enabled,
        criticalOnly: criticalOnly ?? this.criticalOnly,
      );
}

Map<String, dynamic>? parseInjuryAlertEvent(Object? raw) {
  Object? decoded = raw;
  if (raw is String) {
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }
  if (decoded is! Map) return null;
  final event = Map<String, dynamic>.from(decoded);
  if (event['type']?.toString() != 'injury.impact.changed') return null;
  final data = event['data'];
  if (data is! Map) return null;
  final alert = Map<String, dynamic>.from(data);
  alert['eventId'] ??= event['eventId'];
  alert['occurredAt'] ??= event['occurredAt'];
  return alert;
}

bool shouldPresentInjuryAlert(
  Map<String, dynamic> alert,
  InjuryAlertPreferences preferences,
) {
  if (!preferences.enabled) return false;
  if (!preferences.criticalOnly) return true;
  final level = alert['level']?.toString().toUpperCase();
  return level == 'CRITICAL' || level == 'HIGH';
}
