import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';
import 'supabase_service.dart';

enum FoundingReservationResult { available, soldOut, ineligible }

@visibleForTesting
FoundingReservationResult parseFoundingReservationResponse(
  int statusCode,
  String body,
) {
  if (statusCode != 200) {
    throw StateError('Founding Pro availability is temporarily unavailable.');
  }
  final payload = jsonDecode(body);
  if (payload is! Map) {
    throw const FormatException('Invalid Founding Pro availability response.');
  }
  if (payload['available'] == true) {
    return FoundingReservationResult.available;
  }
  return payload['soldOut'] == true
      ? FoundingReservationResult.soldOut
      : FoundingReservationResult.ineligible;
}

class FoundingProReservationService {
  Future<FoundingReservationResult> reserve() async {
    final token = SupabaseService.client?.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty || ApiService.baseUrl.trim().isEmpty) {
      throw StateError('Sign in before claiming Founding Pro.');
    }
    final response = await http
        .post(
          Uri.parse('${ApiService.baseUrl}/api/billing/founding-pro/reserve'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 15));
    return parseFoundingReservationResponse(response.statusCode, response.body);
  }
}
