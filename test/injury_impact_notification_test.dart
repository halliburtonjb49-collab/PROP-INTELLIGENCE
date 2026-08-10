import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/theme/app_colors.dart';
import 'package:prop_intelligence/widgets/main_dashboard.dart';

void main() {
  test('injury impact alert is branded, tappable and dismissible', () {
    var viewCount = 0;
    final snackBar = buildInjuryImpactSnackBar(
      alert: const {
        'title': 'Injury impact changed',
        'message': 'Player markets require another review.',
      },
      onView: () => viewCount += 1,
    );

    expect(snackBar.backgroundColor, const Color(0xFF0B2A42));
    expect(snackBar.showCloseIcon, isTrue);
    expect(snackBar.closeIconColor, AppColors.goldLight);
    expect(snackBar.action?.label, 'VIEW');
    expect(snackBar.action?.textColor, AppColors.goldHighlight);

    final tappableContent = snackBar.content as InkWell;
    expect(tappableContent.onTap, isNotNull);
    tappableContent.onTap!();
    expect(viewCount, 1);

    snackBar.action!.onPressed();
    expect(viewCount, 2);
  });
}
