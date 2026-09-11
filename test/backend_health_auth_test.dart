import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('protected prop health probe authenticates and retries an expired token', () {
    final source = File('lib/services/api_service.dart').readAsStringSync();
    final start = source.indexOf('Future<bool> checkBackendHealth()');
    final end = source.indexOf('Future<PropPage> _fetchPropPage', start);
    final method = source.substring(start, end);

    expect(method, contains("'limit': '1'"));
    expect(method, contains('headers: await _authenticatedHeaders()'));
    expect(method, contains('propsResponse.statusCode == 401'));
    expect(method, contains('_authenticatedHeaders(forceRefresh: true)'));
  });
}
