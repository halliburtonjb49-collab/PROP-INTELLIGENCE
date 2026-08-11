import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class ProviderAvailabilityDashboard extends StatelessWidget {
  const ProviderAvailabilityDashboard({
    super.key,
    required this.data,
    this.recovery = const <String, dynamic>{},
    this.onRecover,
    this.recoverySubmitting = false,
  });

  final Map<String, dynamic> data;
  final Map<String, dynamic> recovery;
  final Future<void> Function(String sport)? onRecover;
  final bool recoverySubmitting;

  Color _statusColor(String status) => switch (status.toUpperCase()) {
    'HEALTHY' => const Color(0xFF65E6B4),
    'PARTIAL' => AppColors.gold,
    'NOT_ENTITLED' => const Color(0xFFFFA65C),
    _ => const Color(0xFFFF7474),
  };

  IconData _statusIcon(String status) => switch (status.toUpperCase()) {
    'HEALTHY' => Icons.verified_rounded,
    'PARTIAL' => Icons.pending_actions_rounded,
    'NOT_ENTITLED' => Icons.lock_outline_rounded,
    _ => Icons.cloud_off_rounded,
  };

  String _time(Object? raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    if (parsed == null) return '--';
    final local = parsed.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.month}/${local.day} $hour:$minute ${local.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    final sports = (data['sports'] as List? ?? const [])
        .whereType<Map>()
        .toList(growable: false);
    final alerts = (data['alerts'] as List? ?? const [])
        .whereType<Map>()
        .toList(growable: false);
    final overall = '${data['overallStatus'] ?? 'UNAVAILABLE'}'.toUpperCase();
    final recoverySports = <String, Map>{
      for (final row
          in (recovery['sports'] as List? ?? const []).whereType<Map>())
        '${row['sport']}': row,
    };

    if (sports.isEmpty) {
      return _emptyState();
    }

    return KeyedSubtree(
      key: const ValueKey('provider-availability-dashboard'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1D2A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _statusColor(overall).withValues(alpha: .55),
              ),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 8,
              spacing: 12,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      overall == 'HEALTHY'
                          ? Icons.monitor_heart_rounded
                          : Icons.notification_important_outlined,
                      color: _statusColor(overall),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      overall == 'HEALTHY'
                          ? 'ALL PROVIDERS HEALTHY'
                          : '${alerts.length} PROVIDER ALERT${alerts.length == 1 ? '' : 'S'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .6,
                      ),
                    ),
                  ],
                ),
                Text(
                  'Checked ${_time(data['checkedAt'] ?? data['generatedAt'])}  |  Refresh every ${data['refreshIntervalMinutes'] ?? 10}m',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _recoveryPanel(),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1080
                  ? 3
                  : constraints.maxWidth >= 680
                  ? 2
                  : 1;
              final width = columns == 1
                  ? constraints.maxWidth
                  : (constraints.maxWidth - ((columns - 1) * 10)) / columns;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: sports
                    .map(
                      (sport) => SizedBox(
                        width: width,
                        child: _sportCard(
                          sport,
                          recoveryAction: recoverySports['${sport['sport']}'],
                        ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
          if (alerts.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...alerts.take(6).map(_alert),
          ],
        ],
      ),
    );
  }

  Widget _recoveryPanel() {
    final state = '${recovery['state'] ?? 'IDLE'}'.toUpperCase();
    final queue = recovery['queue'] as Map? ?? const {};
    final sync = recovery['sync'] as Map? ?? const {};
    final recommended = recovery['recoveryRecommended'] == true;
    final canStart = recovery['canStartRecovery'] == true;
    final active = state == 'RUNNING' || state == 'QUEUED';
    final color = switch (state) {
      'SUCCEEDED' => const Color(0xFF65E6B4),
      'RUNNING' || 'QUEUED' => const Color(0xFF61BFFF),
      'RECOMMENDED' => AppColors.gold,
      'FAILED' => const Color(0xFFFF7474),
      _ => AppColors.textMuted,
    };
    return Container(
      key: const ValueKey('owner-provider-recovery'),
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF071722),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withValues(alpha: .38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 9,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    active
                        ? Icons.sync_rounded
                        : Icons.health_and_safety_outlined,
                    color: color,
                    size: 19,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AUTOMATIC PROVIDER RECOVERY | $state',
                          style: TextStyle(
                            color: color,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${recovery['message'] ?? 'Recovery status is warming up.'}',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (recommended && onRecover != null)
                OutlinedButton.icon(
                  key: const ValueKey('provider-recover-all'),
                  onPressed: canStart && !recoverySubmitting
                      ? () => onRecover!('ALL')
                      : null,
                  icon: recoverySubmitting
                      ? const SizedBox.square(
                          dimension: 13,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 14),
                  label: const Text('RUN SAFE RECOVERY'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.gold,
                    side: BorderSide(
                      color: AppColors.gold.withValues(alpha: .5),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          if (active) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              minHeight: 3,
              color: color,
              backgroundColor: color.withValues(alpha: .12),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'SYNC ${sync['status'] ?? 'idle'} | COVERAGE ${sync['coverageStatus'] ?? 'idle'} | '
            'POST ${sync['postProcessingStatus'] ?? 'idle'} | '
            'WORKERS ${queue['workers'] ?? 0} | QUEUED ${queue['queued'] ?? 0} | '
            'RETRIES ${((queue['retryPolicy'] as Map?)?['maxAttempts'] ?? '--')}',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF0C1823),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.gold.withValues(alpha: .3)),
    ),
    child: const Text(
      'Provider availability is warming up. The next scheduled sync will populate this dashboard.',
      style: TextStyle(color: AppColors.textMuted, fontSize: 11),
    ),
  );

  Widget _sportCard(Map sport, {Map? recoveryAction}) {
    final status = '${sport['status'] ?? 'UNAVAILABLE'}'.toUpperCase();
    final color = _statusColor(status);
    final missing = (sport['missingData'] as List? ?? const [])
        .map((value) => '$value')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1823),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_statusIcon(status), color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${sport['sport'] ?? '--'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status.replaceAll('_', ' '),
                  style: TextStyle(
                    color: color,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '${sport['provider'] ?? '--'} | ${sport['authorizationStatus'] ?? 'UNKNOWN'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metric('GAMES', sport['gamesChecked'] ?? 0),
              _metric('PLAYERS', sport['playersConfirmed'] ?? 0),
              _metric('STARTERS', sport['startersConfirmed'] ?? 0),
              _metric('CREATED', sport['observationsCreated'] ?? 0),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Last success: ${_time(sport['lastSuccessfulSync'])}',
            style: const TextStyle(color: Colors.white70, fontSize: 9),
          ),
          const SizedBox(height: 3),
          Text(
            'Next refresh: ${_time(sport['nextRefreshAt'])}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
          ),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(
              missing.join(' '),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 9, height: 1.35),
            ),
          ],
          if (recoveryAction?['canRecover'] == true && onRecover != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: ValueKey('provider-recover-${sport['sport']}'),
                onPressed: recoverySubmitting
                    ? null
                    : () => onRecover!('${sport['sport']}'),
                icon: const Icon(Icons.refresh_rounded, size: 14),
                label: Text('RECOVER ${sport['sport']}'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color.withValues(alpha: .5)),
                  textStyle: const TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metric(String label, Object value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFF07131D),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      '$label $value',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 8,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _alert(Map alert) {
    final status = '${alert['status'] ?? 'UNAVAILABLE'}';
    final color = _statusColor(status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: color.withValues(alpha: .25)),
        ),
        child: Text(
          '${alert['sport'] ?? 'PROVIDER'} | ${alert['message'] ?? 'Availability needs review.'}',
          style: TextStyle(color: color, fontSize: 9),
        ),
      ),
    );
  }
}
