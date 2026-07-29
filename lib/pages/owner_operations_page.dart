import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_colors.dart';

class OwnerOperationsPage extends StatefulWidget {
  const OwnerOperationsPage({super.key, this.apiService});

  final ApiService? apiService;

  @override
  State<OwnerOperationsPage> createState() => _OwnerOperationsPageState();
}

class _OwnerOperationsPageState extends State<OwnerOperationsPage> {
  late final ApiService _api = widget.apiService ?? ApiService();
  Map<String, dynamic>? _control;
  Map<String, dynamic>? _review;
  bool _loading = true;
  String? _error;
  DateTime? _lastChecked;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        _api.fetchLaunchControlPanel(),
        _api.fetchOwnerGradingReview(),
      ]);
      if (!mounted) return;
      setState(() {
        _control = results[0];
        _review = results[1];
        _lastChecked = DateTime.now();
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map _map(String key) => _control?[key] as Map? ?? const {};

  @override
  Widget build(BuildContext context) {
    final reviewItems = (_review?['items'] as List? ?? const [])
        .whereType<Map>()
        .toList(growable: false);
    final failures =
        (_map('pipelines')['activeFailures'] as List? ?? const [])
            .whereType<Map>()
            .toList(growable: false);
    return ColoredBox(
      color: AppColors.background,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _header(),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _notice(
                Icons.error_outline,
                'Operations data could not be loaded',
                _error!,
                const Color(0xFFFF7B7B),
              ),
            ],
            const SizedBox(height: 16),
            _sectionTitle('SYSTEM STATUS', 'Live production health and capacity'),
            const SizedBox(height: 10),
            _statusGrid(),
            const SizedBox(height: 22),
            _sectionTitle(
              'ISSUES REQUIRING REVIEW',
              'Unsettled legs and grades that need owner attention',
            ),
            const SizedBox(height: 10),
            if (reviewItems.isEmpty)
              _notice(
                Icons.verified_outlined,
                'No grading issues detected',
                'No overdue pending legs or unverified settled grades are currently in the queue.',
                const Color(0xFF8CFFB2),
              )
            else
              ...reviewItems.map(_reviewCard),
            const SizedBox(height: 22),
            _sectionTitle(
              'PIPELINE TRACKING',
              'Recent ingestion, refresh, and grading failures',
            ),
            const SizedBox(height: 10),
            if (failures.isEmpty)
              _notice(
                Icons.account_tree_outlined,
                'Pipelines are healthy',
                'No active pipeline failures were reported.',
                const Color(0xFF8CFFB2),
              )
            else
              ...failures.map(_pipelineCard),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 12,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'OWNER OPERATIONS CENTER',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: .8,
              ),
            ),
            SizedBox(height: 5),
            Text(
              'Private production controls, health signals, and review queues',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
        FilledButton.icon(
          key: const ValueKey('owner-operations-refresh'),
          onPressed: _loading ? null : _refresh,
          icon: _loading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded, size: 18),
          label: Text(_loading ? 'RUNNING CHECKS' : 'RUN ALL CHECKS'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: const Color(0xFF07121C),
          ),
        ),
        if (_lastChecked != null)
          Text(
            'Last checked ${TimeOfDay.fromDateTime(_lastChecked!).format(context)}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
          ),
      ],
    );
  }

  Widget _sectionTitle(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          color: AppColors.gold,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: .8,
        ),
      ),
      const SizedBox(height: 3),
      Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
    ],
  );

  Widget _statusGrid() {
    final api = _map('api');
    final redis = _map('redis');
    final workers = _map('workers');
    final providers = _map('providers');
    final freshness = _map('propFreshness');
    final scoreboard = _map('scoreboardLatency');
    final users = _map('activeUsers');
    final payments = _map('failedPayments');
    final slips = _map('unsettledSlips');
    final review = _map('gradingReview');
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _status('API', api['status'] ?? 'Loading', api['status'] == 'ok'),
        _status('Redis', redis['available'] == true ? 'Connected' : 'Unavailable',
            redis['available'] == true),
        _status('Workers', '${workers['workers'] ?? 0} online',
            workers['available'] == true,
            detail: '${workers['queued'] ?? 0} queued | ${workers['failed'] ?? 0} failed'),
        _status('Provider quality', '${providers['qualityScore'] ?? '--'}',
            (providers['qualityScore'] as num? ?? 0) >= .7,
            detail: '${providers['errors'] ?? 0} errors | ${providers['remainingQuota'] ?? '--'} quota'),
        _status('Prop freshness', '${freshness['ageMinutes'] ?? '--'} min',
            freshness['healthy'] == true,
            detail: '${freshness['total'] ?? 0} props'),
        _status('Scoreboard', '${scoreboard['lastMs'] ?? '--'} ms',
            scoreboard['status'] == 'ok',
            detail: 'p95 ${scoreboard['p95Ms'] ?? '--'} ms'),
        _status('Active users', '${users['count'] ?? '--'}',
            users['instrumented'] == true),
        _status('Failed payments', '${payments['count'] ?? '--'}',
            (payments['count'] ?? 0) == 0),
        _status('Unsettled slips', '${slips['count'] ?? '--'}', true),
        _status('Questionable grades', '${review['questionableCount'] ?? '--'}',
            (review['questionableCount'] ?? 0) == 0),
        _status('Deployment', _shortVersion(api['version']), true),
      ],
    );
  }

  String _shortVersion(Object? value) {
    final text = value?.toString() ?? 'Unknown';
    return text.length > 10 ? text.substring(0, 10) : text;
  }

  Widget _status(
    String label,
    String value,
    bool healthy, {
    String? detail,
  }) {
    final color = healthy ? const Color(0xFF8CFFB2) : const Color(0xFFFFD166);
    return Container(
      width: 205,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1823),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          Text(value.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w900)),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(detail, style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
          ],
        ],
      ),
    );
  }

  Widget _reviewCard(Map item) {
    final reasons = (item['reasons'] as List? ?? const []).join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _notice(
        Icons.fact_check_outlined,
        '${item['player'] ?? 'Unknown player'} | ${item['market'] ?? 'Unknown market'}',
        '${item['side'] ?? ''} ${item['line'] ?? ''} | ${item['sport'] ?? ''} | $reasons',
        const Color(0xFFFFD166),
        trailing: 'Slip ${item['slipId'] ?? '--'}',
      ),
    );
  }

  Widget _pipelineCard(Map item) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: _notice(
      Icons.warning_amber_rounded,
      item['pipeline']?.toString() ?? item['name']?.toString() ?? 'Pipeline issue',
      (item['errors'] as List? ?? [item['status'] ?? 'Review required']).join(' | '),
      const Color(0xFFFF7B7B),
    ),
  );

  Widget _notice(
    IconData icon,
    String title,
    String detail,
    Color color, {
    String? trailing,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF0C1823),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: .25)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(detail, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
            ],
          ),
        ),
        if (trailing != null)
          Text(trailing, style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
      ],
    ),
  );
}
