import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/widgets/owner_command_center_overview.dart';

void main() {
  testWidgets('owner inventory exposes reversible prop and alert controls', (
    tester,
  ) async {
    Map? controlledProp;
    bool? quarantineRequested;
    Map? controlledAlert;
    bool? acknowledgementRequested;
    final data = <String, dynamic>{
      'total': 1,
      'healthy': 0,
      'flagged': 1,
      'quarantined': 0,
      'facets': {
        'sports': ['WNBA'],
        'providers': ['PrizePicks'],
        'quality': ['stale_line'],
      },
      'alerts': [
        {
          'id': 'inventory:stale_line',
          'key': 'stale_line',
          'count': 1,
          'severity': 'GOLD',
          'acknowledged': false,
        },
      ],
      'providers': <Map<String, dynamic>>[],
      'items': [
        {
          'id': 'control-key',
          'gameId': 'game-1',
          'sport': 'WNBA',
          'matchup': 'Away vs Home',
          'player': 'Test Player',
          'market': 'Points',
          'provider': 'PrizePicks',
          'line': 20.5,
          'prediction': 'OVER',
          'confidence': .72,
          'lastUpdate': '2026-08-11T12:00:00Z',
          'warnings': ['stale_line'],
          'quarantined': false,
        },
      ],
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: OwnerPropInventoryPanel(
              data: data,
              onPropControl: (item, quarantined) async {
                controlledProp = item;
                quarantineRequested = quarantined;
              },
              onAlertAcknowledgement: (alert, acknowledged) async {
                controlledAlert = alert;
                acknowledgementRequested = acknowledged;
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('owner-alert-inventory:stale_line')));
    await tester.pump();
    expect(controlledAlert?['id'], 'inventory:stale_line');
    expect(acknowledgementRequested, isTrue);

    await tester.ensureVisible(find.byKey(const ValueKey('owner-prop-control-control-key')));
    await tester.tap(find.byKey(const ValueKey('owner-prop-control-control-key')));
    await tester.pump();
    expect(controlledProp?['id'], 'control-key');
    expect(quarantineRequested, isTrue);
  });
}
