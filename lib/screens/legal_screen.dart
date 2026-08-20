import 'package:flutter/material.dart';

import '../legal/legal_content.dart';
import '../theme/app_colors.dart';

/// Terms and privacy, reachable from inside the app.
///
/// This text was previously only on the login screen, behind a dialog a
/// signed-in member has no way back to. Terms a user cannot re-read are
/// terms they cannot check.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, this.initialTab = 0});

  final int initialTab;

  static const routeName = '/legal';

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab.clamp(0, 1),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.sidebar,
          foregroundColor: Colors.white,
          title: const Text(
            'TERMS & PRIVACY',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
          ),
          bottom: const TabBar(
            indicatorColor: AppColors.gold,
            labelColor: AppColors.gold,
            unselectedLabelColor: Colors.white,
            labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
            tabs: [
              Tab(text: 'TERMS'),
              Tab(text: 'PRIVACY'),
            ],
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              _SectionList(
                key: const ValueKey('legal-terms'),
                sections: termsSections,
                footer:
                    'Play only where lawful and only if you meet the legal '
                    'age in your location. Problem gambling? Call '
                    '$legalHelpLine.',
              ),
              _SectionList(
                key: const ValueKey('legal-privacy'),
                sections: privacySections,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionList extends StatelessWidget {
  const _SectionList({super.key, required this.sections, this.footer});

  final List<LegalSection> sections;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        for (final section in sections) LegalSectionView(section: section),
        if (footer != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.sidebar,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.gold),
            ),
            child: Text(
              footer!,
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 11,
                height: 1.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    );
  }
}
