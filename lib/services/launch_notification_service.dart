import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_service.dart';

/// Service to handle launch notification email subscriptions
class LaunchNotificationService {
  static const String _localStorageKey = 'launch_notification_subscribed';

  /// Check if the user has already subscribed locally
  Future<bool> hasSubscribed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_localStorageKey) ?? false;
    } catch (error) {
      debugPrint('Error checking subscription status: $error');
      return false;
    }
  }

  /// Subscribe a user for launch notifications
  Future<bool> subscribeForLaunch(String email) async {
    try {
      // Try to save to Supabase if available
      if (SupabaseService.isConfigured && SupabaseService.isInitialized) {
        await _saveToSupabase(email);
      }

      // Always save locally as a backup
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_localStorageKey, true);
      await prefs.setString('${_localStorageKey}_email', email);

      debugPrint('Launch notification subscription successful: $email');
      return true;
    } catch (error) {
      debugPrint('Error subscribing for launch notifications: $error');
      
      // Even if Supabase fails, try to save locally
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_localStorageKey, true);
        await prefs.setString('${_localStorageKey}_email', email);
        return true;
      } catch (localError) {
        debugPrint('Local storage also failed: $localError');
        return false;
      }
    }
  }

  /// Save email to Supabase database
  Future<void> _saveToSupabase(String email) async {
    final client = SupabaseService.client;
    if (client == null) {
      throw Exception('Supabase client not available');
    }

    // Create or update the launch_notifications table entry
    await client.from('launch_notifications').upsert(
      {
        'email': email,
        'subscribed_at': DateTime.now().toIso8601String(),
        'status': 'active',
      },
      onConflict: 'email',
    );

    debugPrint('Email saved to Supabase: $email');
  }

  /// Clear local subscription status (for testing purposes)
  Future<void> clearLocalSubscription() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_localStorageKey);
      await prefs.remove('${_localStorageKey}_email');
      debugPrint('Local subscription cleared');
    } catch (error) {
      debugPrint('Error clearing local subscription: $error');
    }
  }

  /// Get the locally stored email (if any)
  Future<String?> getLocalEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('${_localStorageKey}_email');
    } catch (error) {
      debugPrint('Error getting local email: $error');
      return null;
    }
  }
}
