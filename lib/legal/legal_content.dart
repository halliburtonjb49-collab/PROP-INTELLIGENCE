import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// One copy of the legal text, shown wherever it is needed.
///
/// It lived only inside the login screen's dialog, which a member sees once
/// and cannot reach again afterwards. Extracting it is not tidiness: two
/// copies of legal wording drift, and the stale copy is the one that ends up
/// in front of somebody.
class LegalSection {
  const LegalSection({required this.title, required this.text});

  final String title;
  final String text;
}

const termsSections = <LegalSection>[
  LegalSection(
    title: 'SUBSCRIPTIONS & BILLING',
    text:
        'Core is \$24.99 per month, Pro is \$59.99 per month, and Founding Pro is \$49.99 per month for the first 100 members. Monthly plans include a 2-day free trial; annual plans include a 7-day free trial. Subscriptions renew automatically until canceled. Prices and applicable taxes are shown before purchase.',
  ),
  LegalSection(
    title: 'CANCELLATION & ACCESS',
    text:
        'You may cancel at any time through the billing portal or the platform used to purchase. Cancellation stops future renewals; access generally continues through the end of the paid billing period.',
  ),
  LegalSection(
    title: 'REFUNDS',
    text:
        'Except where required by law, subscription charges are non-refundable once a billing period begins. Contact support promptly if you believe a charge was made in error.',
  ),
  LegalSection(
    title: 'INFORMATIONAL SERVICE',
    text:
        'PROP INTELLIGENCE provides sports information, analytics, projections and organizational tools. Results are estimates, not guarantees. Nothing in the service is financial, legal or gambling advice.',
  ),
  LegalSection(
    title: 'LAWFUL USE & YOUR DECISIONS',
    text:
        'PROP INTELLIGENCE is a research, analytics and tracking service. It does not accept wagers, hold funds or settle outcomes. Any decision you make using the service is your own, and you are responsible for using it only where lawful and only if you meet the age requirement that applies to you.',
  ),
  LegalSection(
    title: 'ACCOUNT RESPONSIBILITIES',
    text:
        'Keep your credentials secure, provide accurate account information and do not share, resell, scrape, reverse engineer or misuse the service. You are responsible for activity under your account.',
  ),
  LegalSection(
    title: 'AVAILABILITY & LIABILITY',
    text:
        'Data may be delayed, incomplete or inaccurate, and features may change. Always verify live lines and market rules. To the fullest extent permitted by law, use of the service is at your own risk.',
  ),
  LegalSection(
    title: 'SUPPORT & EFFECTIVE DATE',
    text:
        'Questions: propsintell@gmail.com. Effective July 18, 2026. The complete published Terms and Privacy Policy govern use of the service.',
  ),
];

const privacySections = <LegalSection>[
  LegalSection(
    title: 'DATA WE COLLECT',
    text:
        'We collect account details, authentication identifiers, subscription status, saved props and slips, chat activity, notification subscription identifiers, and technical usage information needed to operate and secure the service.',
  ),
  LegalSection(
    title: 'HOW DATA IS USED',
    text:
        'Data is used to provide personalized research tools, synchronize your account, process subscriptions, deliver requested notifications, prevent abuse, diagnose failures, and improve product reliability and model performance.',
  ),
  LegalSection(
    title: 'SERVICE PROVIDERS',
    text:
        'We use contracted providers for authentication and storage, sports data, payments, application hosting, analytics, and notifications. Each provider processes only the information needed for its service and is governed by its own privacy terms.',
  ),
  LegalSection(
    title: 'BOT AND ABUSE PROTECTION',
    text:
        'We use Cloudflare Turnstile to help distinguish legitimate users from automated abuse during authentication. Turnstile is subject to Cloudflare’s Turnstile Privacy Addendum: https://www.cloudflare.com/turnstile-privacy-policy/.',
  ),
  LegalSection(
    title: 'SHARING & SALES',
    text:
        'We do not sell personal information. Information may be disclosed to service providers, when required by law, to protect users or the service, or as part of a business transfer subject to applicable safeguards.',
  ),
  LegalSection(
    title: 'RETENTION & SECURITY',
    text:
        'We retain information only as long as reasonably needed for the purposes described, legal obligations, fraud prevention, and dispute resolution. We use reasonable safeguards, but no online system can guarantee absolute security.',
  ),
  LegalSection(
    title: 'YOUR CHOICES',
    text:
        'You can disable notifications in device or browser settings and manage or cancel subscriptions through the purchase platform. You may permanently delete your account and associated eligible data from Account > Delete Account. You may also contact support to request access or correction.',
  ),
  LegalSection(
    title: 'CONTACT & EFFECTIVE DATE',
    text:
        'Privacy questions and account-data requests: propsintell@gmail.com. Effective July 29, 2026. Rights may vary based on your location.',
  ),
];

/// Renders one section identically on every surface that shows it.
class LegalSectionView extends StatelessWidget {
  const LegalSectionView({super.key, required this.section});

  final LegalSection section;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: const TextStyle(
              color: AppColors.gold,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            section.text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}
