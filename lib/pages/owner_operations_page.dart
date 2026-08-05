import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_colors.dart' as brand_colors;

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
    final failures = (_map('pipelines')['activeFailures'] as List? ?? const [])
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
            _sectionTitle(
              'SYSTEM STATUS',
              'Live production health and capacity',
            ),
            const SizedBox(height: 10),
            _statusGrid(),
            const SizedBox(height: 22),
            _sectionTitle(
              'MODEL ACCOUNTABILITY',
              'Out-of-sample accuracy, calibration, closing-line value, and prediction coverage',
            ),
            const SizedBox(height: 10),
            _modelAccountability(),
            const SizedBox(height: 22),
            _sectionTitle(
              'OWNER-ONLY STRIKEOUT INTELLIGENCE',
              'Log5 and binomial validation with environmental adjustments for MLB strikeout props',
            ),
            const SizedBox(height: 10),
            _strikeoutIntelligence(),
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
      Text(
        subtitle,
        style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
      ),
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
    final syncDiagnostics = _map('syncDiagnostics');
    final syncCategories = (syncDiagnostics['categories'] as List? ?? const [])
        .whereType<Map>()
        .take(3)
        .map((item) => '${item['category']}: ${item['count']}')
        .join(' | ');
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _status('API', api['status'] ?? 'Loading', api['status'] == 'ok'),
        _status(
          'Redis',
          redis['available'] == true ? 'Connected' : 'Unavailable',
          redis['available'] == true,
        ),
        _status(
          'Workers',
          '${workers['workers'] ?? 0} online',
          workers['available'] == true,
          detail:
              '${workers['queued'] ?? 0} queued | ${workers['failed'] ?? 0} failed',
        ),
        _status(
          'Provider quality',
          '${providers['qualityScore'] ?? '--'}',
          (providers['qualityScore'] as num? ?? 0) >= .7,
          detail:
              '${providers['errors'] ?? 0} errors | ${providers['remainingQuota'] ?? '--'} quota',
        ),
        _status(
          'Prop freshness',
          '${freshness['ageMinutes'] ?? '--'} min',
          freshness['healthy'] == true,
          detail: '${freshness['total'] ?? 0} props',
        ),
        _status(
          'Scoreboard',
          '${scoreboard['lastMs'] ?? '--'} ms',
          scoreboard['status'] == 'ok',
          detail: 'p95 ${scoreboard['p95Ms'] ?? '--'} ms',
        ),
        _status(
          'Active users',
          '${users['count'] ?? '--'}',
          users['instrumented'] == true,
        ),
        _status(
          'Failed payments',
          '${payments['count'] ?? '--'}',
          (payments['count'] ?? 0) == 0,
        ),
        _status('Unsettled slips', '${slips['count'] ?? '--'}', true),
        _status(
          'Questionable grades',
          '${review['questionableCount'] ?? '--'}',
          (review['questionableCount'] ?? 0) == 0,
        ),
        _status(
          'Ticket sync reports',
          '${syncDiagnostics['last24Hours'] ?? 0} today',
          (syncDiagnostics['last24Hours'] ?? 0) == 0,
          detail: syncCategories.isEmpty
              ? 'No reports in 7 days'
              : syncCategories,
        ),
        _status('Deployment', _shortVersion(api['version']), true),
      ],
    );
  }

  Widget _modelAccountability() {
    final performance = _map('modelPerformance');
    final operations = _map('predictionOperations');
    final clv = performance['clv'] as Map? ?? const {};
    final sample = (performance['sampleSize'] as num?)?.toInt() ?? 0;
    final accuracy = (performance['accuracy'] as num?)?.toDouble();
    final brier = (performance['brierScore'] as num?)?.toDouble();
    final calibrated = performance['calibrated'] == true;
    final beatClose = (clv['beatClosingLineRate'] as num?)?.toDouble();
    final oddsClv = (clv['averageOddsClvExpectedValuePercent'] as num?)
        ?.toDouble();
    final positiveOddsClv = (clv['positiveOddsClvRate'] as num?)?.toDouble();
    final segments = (performance['qualitySegments'] as List? ?? const [])
        .whereType<Map>()
        .take(6)
        .toList(growable: false);
    final sideSegments = (performance['sideSegments'] as List? ?? const [])
        .whereType<Map>()
        .take(8)
        .toList(growable: false);
    final audit = performance['auditSummary'] as Map? ?? const {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _status(
              'Graded sample',
              '$sample / ${performance['minimumCalibrationSample'] ?? 100}',
              calibrated,
              detail: calibrated ? 'Calibration active' : 'Still warming',
            ),
            _status(
              'Accuracy',
              accuracy == null
                  ? '--'
                  : '${(accuracy * 100).toStringAsFixed(1)}%',
              sample > 0,
              detail: 'Out-of-sample only',
            ),
            _status(
              'Brier score',
              brier?.toStringAsFixed(3) ?? '--',
              brier != null,
              detail: 'Lower is better',
            ),
            _status(
              'Beat closing line',
              beatClose == null
                  ? '--'
                  : '${(beatClose * 100).toStringAsFixed(1)}%',
              beatClose != null && beatClose >= .5,
              detail: '${clv['sampleSize'] ?? 0} captured closes',
            ),
            _status(
              'Vig-free odds CLV',
              oddsClv == null ? '--' : '${oddsClv.toStringAsFixed(2)}%',
              oddsClv != null && oddsClv > 0,
              detail: positiveOddsClv == null
                  ? '${clv['oddsSampleSize'] ?? 0} paired closes'
                  : '${(positiveOddsClv * 100).toStringAsFixed(1)}% positive • ${clv['oddsSampleSize'] ?? 0} paired closes',
            ),
            _status(
              'Snapshots today',
              '${operations['snapshotsToday'] ?? 0}',
              operations['databaseConfigured'] == true,
              detail: '${operations['pendingPredictions'] ?? 0} pending grades',
            ),
          ],
        ),
        if (segments.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'TOP VERIFIED SEGMENTS',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          ...segments.map((segment) {
            final segmentAccuracy = (segment['accuracy'] as num?)?.toDouble();
            final averageConfidence = (segment['averageConfidence'] as num?)
                ?.toDouble();
            final calibrationGap = (segment['calibrationGap'] as num?)
                ?.toDouble();
            return Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: _notice(
                Icons.analytics_outlined,
                '${segment['sport'] ?? '--'} | ${segment['category'] ?? '--'} | ${segment['provider'] ?? '--'}',
                '${segment['sampleSize'] ?? 0} picks | '
                    'accuracy ${segmentAccuracy == null ? '--' : '${(segmentAccuracy * 100).toStringAsFixed(1)}%'} | '
                    'confidence ${averageConfidence == null ? '--' : '${(averageConfidence * 100).toStringAsFixed(1)}%'} | '
                    'gap ${calibrationGap == null ? '--' : '${(calibrationGap * 100).toStringAsFixed(1)} pts'}',
                AppColors.gold,
              ),
            );
          }),
        ],
        if (sideSegments.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'OVER / UNDER AUDIT',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${audit['healthy'] ?? 0} healthy  |  ${audit['monitor'] ?? 0} monitor  |  ${audit['recalibrate'] ?? 0} recalibrate  |  ${audit['collecting'] ?? 0} collecting',
            style: const TextStyle(fontSize: 9, color: AppColors.textMuted),
          ),
          const SizedBox(height: 7),
          ...sideSegments.map((segment) {
            final status = '${segment['status'] ?? 'COLLECTING'}';
            final segmentAccuracy = (segment['accuracy'] as num?)?.toDouble();
            final gap = (segment['calibrationGap'] as num?)?.toDouble();
            final healthy = status == 'HEALTHY';
            return Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: _notice(
                healthy ? Icons.verified_outlined : Icons.rule_outlined,
                '${segment['sport'] ?? '--'} | ${segment['side'] ?? '--'} | ${segment['confidenceTier'] ?? '--'} | $status',
                '${segment['sampleSize'] ?? 0} picks | accuracy ${segmentAccuracy == null ? '--' : '${(segmentAccuracy * 100).toStringAsFixed(1)}%'} | gap ${gap == null ? '--' : '${(gap * 100).toStringAsFixed(1)} pts'} | ${segment['reason'] ?? ''}',
                healthy ? const Color(0xFF8CFFB2) : AppColors.gold,
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _strikeoutIntelligence() {
    final ownerInsights = _control?['ownerOnlyInsights'] as Map? ?? const {};
    final strikeout = ownerInsights['strikeoutIntelligence'] as Map? ?? const {};
    final inputCoverage = ownerInsights['strikeoutInputCoverage'] as Map? ?? const {};
    final methodAudit = ownerInsights['strikeoutMethodAudit'] as Map? ?? const {};
    final available = strikeout['available'] == true;
    if (!available) {
      return _notice(
        Icons.analytics_outlined,
        'Strikeout Report Not Ready',
        strikeout['reason']?.toString() ??
            'No graded MLB strikeout predictions are available yet.',
        AppColors.gold,
      );
    }

    String pct(Object? value) {
      final numeric = (value as num?)?.toDouble();
      return numeric == null ? '--' : '${(numeric * 100).toStringAsFixed(1)}%';
    }

    String numVal(Object? value, {int decimals = 2}) {
      final numeric = (value as num?)?.toDouble();
      return numeric == null ? '--' : numeric.toStringAsFixed(decimals);
    }

    final over = strikeout['over'] as Map? ?? const {};
    final under = strikeout['under'] as Map? ?? const {};
    final methods = (methodAudit['methods'] as List? ?? const [])
      .whereType<Map>()
      .take(3)
      .toList(growable: false);
    final health = (strikeout['health']?.toString() ?? 'COLLECTING').toUpperCase();
    final healthy = health == 'HEALTHY';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _status(
              'Report health',
              health,
              healthy,
              detail: 'Visibility: owner only',
            ),
            _status(
              'Graded strikeout sample',
              '${strikeout['sampleSize'] ?? 0}',
              ((strikeout['sampleSize'] as num?)?.toInt() ?? 0) >= 40,
              detail: 'Suggestive picks tier: ${strikeout['suggestivePickTier'] ?? 'pro_gold'}',
            ),
            _status(
              'Strikeout accuracy',
              pct(strikeout['accuracy']),
              ((strikeout['accuracy'] as num?)?.toDouble() ?? 0) >= 0.5,
              detail: 'All MLB strikeout sides',
            ),
            _status(
              'Strikeout ROI',
              '${numVal(strikeout['simulatedRoi'])}%',
              ((strikeout['simulatedRoi'] as num?)?.toDouble() ?? 0) > 0,
              detail: 'Simulated average return',
            ),
            _status(
              'Beat closing line',
              pct(strikeout['beatClosingLineRate']),
              ((strikeout['beatClosingLineRate'] as num?)?.toDouble() ?? 0) >= 0.5,
              detail: '${strikeout['oddsSampleSize'] ?? 0} odds pairs',
            ),
            _status(
              'Positive odds CLV',
              pct(strikeout['positiveOddsClvRate']),
              ((strikeout['positiveOddsClvRate'] as num?)?.toDouble() ?? 0) >= 0.5,
              detail: '${numVal(strikeout['averageOddsClvExpectedValuePercent'])}% avg',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _notice(
          Icons.security_outlined,
          'Owner-Only Visibility Guard',
          'Strikeout suggestive picks are shown only to Pro Gold users. Owner Operations exposes full validation telemetry for oversight.',
          AppColors.gold,
        ),
        const SizedBox(height: 10),
        if (inputCoverage['available'] == true)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _status(
                'Live strikeout props',
                '${inputCoverage['total'] ?? 0}',
                (inputCoverage['total'] as num? ?? 0) > 0,
                detail: 'Current cached MLB strikeout rows',
              ),
              _status(
                'Full-model coverage',
                pct(inputCoverage['fullModelCoverage']),
                ((inputCoverage['fullModelCoverage'] as num?)?.toDouble() ?? 0) >= .6,
                detail: 'Real matchup rate plus TBF inputs present',
              ),
              _status(
                'Fallback rate',
                pct(inputCoverage['fallbackRate']),
                ((inputCoverage['fallbackRate'] as num?)?.toDouble() ?? 1) <= .4,
                detail: 'Live props still leaning on defaults',
              ),
              _status(
                'CSW coverage',
                pct(inputCoverage['pitcherCswCoverage']),
                ((inputCoverage['pitcherCswCoverage'] as num?)?.toDouble() ?? 0) >= .5,
                detail: 'Pitcher CSW present in cache',
              ),
              _status(
                'Lineup handedness',
                pct(inputCoverage['lineupKCoverage']),
                ((inputCoverage['lineupKCoverage'] as num?)?.toDouble() ?? 0) >= .5,
                detail: 'Lineup K% vs handedness present',
              ),
              _status(
                'Environment coverage',
                pct(inputCoverage['environmentCoverage']),
                ((inputCoverage['environmentCoverage'] as num?)?.toDouble() ?? 0) >= .5,
                detail: 'Temp, umpire, and park loaded',
              ),
            ],
          )
        else
          _notice(
            Icons.storage_outlined,
            'Strikeout Input Coverage Unavailable',
            inputCoverage['reason']?.toString() ??
                'Live strikeout input coverage is not available yet.',
            AppColors.gold,
          ),
        const SizedBox(height: 10),
        _notice(
          Icons.trending_up,
          'OVER Side',
          '${over['sampleSize'] ?? 0} picks | accuracy ${pct(over['accuracy'])} | ROI ${numVal(over['simulatedRoi'])}% | beat close ${pct(over['beatClosingLineRate'])}',
          const Color(0xFF8CFFB2),
        ),
        const SizedBox(height: 8),
        _notice(
          Icons.trending_down,
          'UNDER Side',
          '${under['sampleSize'] ?? 0} picks | accuracy ${pct(under['accuracy'])} | ROI ${numVal(under['simulatedRoi'])}% | beat close ${pct(under['beatClosingLineRate'])}',
          AppColors.gold,
        ),
        if (methods.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'GRADED METHOD AUDIT',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          ...methods.map((method) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _notice(
                  Icons.science_outlined,
                  '${method['method'] ?? 'unknown'} | ${method['sampleSize'] ?? 0} graded',
                  'accuracy ${pct(method['accuracy'])} | fallback pitcher ${pct(method['fallbackPitcherRate'])} | fallback lineup ${pct(method['fallbackLineupRate'])} | fallback TBF ${pct(method['fallbackTbfRate'])} | market blend ${pct(method['marketBlendRate'])}',
                  AppColors.gold,
                ),
              )),
        ],
      ],
    );
  }

  String _shortVersion(Object? value) {
    final text = value?.toString() ?? 'Unknown';
    return text.length > 10 ? text.substring(0, 10) : text;
  }

  Widget _status(String label, String value, bool healthy, {String? detail}) {
    final color = healthy
        ? const Color(0xFF8CFFB2)
        : brand_colors.AppColors.goldHighlight;
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
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            value.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(
              detail,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
            ),
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
        brand_colors.AppColors.goldHighlight,
        trailing: 'Slip ${item['slipId'] ?? '--'}',
      ),
    );
  }

  Widget _pipelineCard(Map item) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: _notice(
      Icons.warning_amber_rounded,
      item['pipeline']?.toString() ??
          item['name']?.toString() ??
          'Pipeline issue',
      (item['errors'] as List? ?? [item['status'] ?? 'Review required']).join(
        ' | ',
      ),
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
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null)
          Text(
            trailing,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
          ),
      ],
    ),
  );
}
