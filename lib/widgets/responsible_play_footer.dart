import 'package:flutter/material.dart';

import '../legal/legal_content.dart';
import '../theme/app_colors.dart';

/// The disclaimer and help line, wherever the board is.
///
/// This copy already existed on the login screen, which a member sees once
/// and then never again. The place it has to be legible is the screen where
/// picks are acted on, and the help line is the part that was missing
/// entirely: the app carried no problem-gambling resource anywhere.
///
/// Deliberately one line and 9pt. A disclaimer that costs a row of the board
/// gets removed by whoever needs the space next, and one that is never shown
/// protects nobody.
class ResponsiblePlayFooter extends StatelessWidget {
  const ResponsiblePlayFooter({super.key, this.onOpenLegal});

  /// Opens the full terms and privacy text. Null hides the affordance rather
  /// than offering a control that goes nowhere.
  final VoidCallback? onOpenLegal;

  /// Re-exported from the legal source so the number shown here and the
  /// number in the terms can never differ.
  static const helpLine = legalHelpLine;

  static const disclaimer =
      'Informational and entertainment purposes only. Not gambling advice. '
      'Play only where lawful and only if you meet the legal age in your '
      'location.';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$disclaimer Problem gambling help: $helpLine.',
      child: Container(
        key: const ValueKey('responsible-play-footer'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 2,
          children: [
            const Text(
              disclaimer,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.silver,
                fontSize: 9,
                height: 1.3,
              ),
            ),
            const Text(
              'Problem gambling? Call $legalHelpLine',
              style: TextStyle(
                color: AppColors.gold,
                fontSize: 9,
                height: 1.3,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (onOpenLegal != null)
              InkWell(
                key: const ValueKey('footer-open-legal'),
                onTap: onOpenLegal,
                child: const Text(
                  'Terms & Privacy',
                  style: TextStyle(
                    color: AppColors.silver,
                    fontSize: 9,
                    height: 1.3,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
