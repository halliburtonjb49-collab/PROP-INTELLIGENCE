import 'package:flutter/material.dart';

class PropIntelligenceBrandedLogo extends StatelessWidget {
  final double height;
  final bool showSubtext;

  const PropIntelligenceBrandedLogo({
    super.key,
    this.height = 120,
    this.showSubtext = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: height,
          height: height,
          child: ClipOval(
            child: Image.asset(
              'assets/branding/prop_intelligence_logo.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: const Color(0xFFF3C344),
                      size: height * 0.35,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'LOGO UNAVAILABLE',
                      style: TextStyle(
                        color: Color(0xFFF3C344),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        if (showSubtext) ...[
          const SizedBox(height: 12),
          const Text(
            'PROP INTELLIGENCE',
            style: TextStyle(
              color: Color(0xFFF3C344),
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 2.5,
            ),
          ),
        ],
      ],
    );
  }
}
