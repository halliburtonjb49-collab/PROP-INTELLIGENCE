import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class PropAlertData {
  const PropAlertData({
    required this.sport,
    required this.title,
    required this.message,
    required this.edge,
    required this.book,
    required this.time,
  });

  final String sport;
  final String title;
  final String message;
  final int edge;
  final String book;
  final String time;
}

class PropAlertsPage extends StatelessWidget {
  const PropAlertsPage({super.key, required this.alerts, this.onClose});

  final List<PropAlertData> alerts;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
        children: [
          Row(
            children: [
              const Icon(
                Icons.notifications_active,
                color: AppColors.gold,
                size: 22,
              ),
              const SizedBox(width: 10),
              const Text(
                'PROP ALERTS',
                style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                '${alerts.length} alerts',
                key: const ValueKey('prop-alert-count'),
                style: const TextStyle(
                  color: Color(0xFF9DAEC0),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Close prop alerts',
                onPressed: onClose ?? () => Navigator.maybePop(context),
                icon: const Icon(Icons.close_rounded),
                color: AppColors.gold,
                iconSize: 24,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (alerts.isEmpty)
            Container(
              key: const ValueKey('prop-alerts-empty-state'),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 34),
              decoration: BoxDecoration(
                color: const Color(0xFF0A1C2B).withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.28),
                ),
              ),
              child: const Column(
                children: [
                  Icon(Icons.sync_rounded, color: AppColors.gold, size: 34),
                  SizedBox(height: 12),
                  Text(
                    'SYNCING PROP ALERTS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 7),
                  Text(
                    'No live alerts right now. Real alerts will appear automatically when a qualifying prop signal is detected.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFC9D4DF),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            )
          else
            ...alerts.map((alert) => PropAlertCard(alert: alert)),
        ],
      ),
    );
  }
}

class PropAlertCard extends StatelessWidget {
  const PropAlertCard({super.key, required this.alert});

  final PropAlertData alert;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1C2B).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.gold,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  alert.sport,
                  style: const TextStyle(
                    color: AppColors.bgBase,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                alert.time,
                style: const TextStyle(color: Color(0xFF9DAEC0), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            alert.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            alert.message,
            style: const TextStyle(
              color: Color(0xFFC9D4DF),
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              Text(
                'Edge: ${alert.edge}%',
                style: const TextStyle(
                  color: AppColors.gold,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Book: ${alert.book}',
                style: const TextStyle(
                  color: AppColors.gold,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
