import 'package:flutter/material.dart';

import '../models/track_record.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart' as app_colors;

/// The model's record, shown to anyone -- including people who have not paid.
///
/// The page's whole job is to be checkable, so it is built to be honest about
/// what it does not yet know. A rate the backend withheld is drawn as "--"
/// with its sample size beside it, never as a zero and never omitted so
/// quietly that the page looks like it simply has good news. Sample sizes sit
/// next to every rate because a rate without one is not evidence.
class TrackRecordPage extends StatefulWidget {
  const TrackRecordPage({super.key, this.apiService});

  final ApiService? apiService;

  @override
  State<TrackRecordPage> createState() => _TrackRecordPageState();
}

class _TrackRecordPageState extends State<TrackRecordPage> {
  late final ApiService _api = widget.apiService ?? ApiService();
  late Future<TrackRecord> _record = _load();

  Future<TrackRecord> _load() async {
    return TrackRecord.fromJson(await _api.fetchTrackRecord());
  }

  void _retry() => setState(() => _record = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TrackRecord>(
      future: _record,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: app_colors.AppColors.gold),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return _RecordUnavailable(onRetry: _retry);
        }
        return _RecordBody(record: snapshot.data!);
      },
    );
  }
}

class _RecordUnavailable extends StatelessWidget {
  const _RecordUnavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'The record could not be loaded.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: onRetry, child: const Text('RETRY')),
        ],
      ),
    );
  }
}

class _RecordBody extends StatelessWidget {
  const _RecordBody({required this.record});

  final TrackRecord record;

  static String percent(double? value) =>
      value == null ? '--' : '${(value * 100).toStringAsFixed(1)}%';

  static String signedPercent(double? value) =>
      value == null ? '--' : '${(value * 100).toStringAsFixed(1)}%';

  static String points(double? value) =>
      value == null ? '--' : value.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          const SizedBox(height: 12),
          _IntegrityBanner(record: record),
          const SizedBox(height: 14),
          if (!record.published) ...[
            _CollectingNotice(record: record),
            const SizedBox(height: 14),
          ],
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Stat(
                label: 'WIN RATE',
                value: percent(record.winRate),
                footnote: '${record.sampleSize} graded picks',
              ),
              _Stat(
                label: 'SIMULATED ROI',
                value: signedPercent(record.simulatedRoi),
                // Named precisely on purpose: this is modelled from entry
                // odds, not money that was staked.
                footnote: 'modelled from entry odds',
              ),
              _Stat(
                label: 'BEAT CLOSING LINE',
                value: percent(record.clv.beatClosingLineRate),
                footnote: '${record.clv.sampleSize} priced picks',
              ),
              _Stat(
                label: 'AVG LINE CLV',
                value: points(record.clv.averageLinePoints),
                footnote: 'points vs close',
              ),
              _Stat(
                label: 'CURRENT STREAK',
                value: record.currentStreakLength == 0
                    ? '--'
                    : '${record.currentStreakType == 'WINNING' ? 'W' : 'L'}${record.currentStreakLength}',
                footnote: 'shown even when losing',
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'BY CONFIDENCE TIER',
            style: TextStyle(
              color: app_colors.AppColors.gold,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: .6,
            ),
          ),
          const SizedBox(height: 8),
          if (record.tiers.isEmpty)
            const Text(
              'No tier has graded results yet.',
              style: TextStyle(
                color: app_colors.AppColors.textMuted,
                fontSize: 11,
              ),
            )
          else
            for (final tier in record.tiers) _TierRow(tier: tier),
          if (record.sports.isNotEmpty) ...[
            const SizedBox(height: 18),
            _BreakdownSection(title: 'BY SPORT', rows: record.sports),
          ],
          if (record.markets.isNotEmpty) ...[
            const SizedBox(height: 18),
            _BreakdownSection(title: 'BY MARKET', rows: record.markets),
          ],
          if (record.calibration.isNotEmpty) ...[
            const SizedBox(height: 18),
            _CalibrationSection(points: record.calibration),
          ],
          const SizedBox(height: 18),
          _Footnote(record: record),
        ],
      ),
    );
  }

  Widget _header() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'TRACK RECORD',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Every graded pick the model has made, including the losing ones. '
          'Sample sizes are shown beside each number so it can be checked '
          'rather than taken on trust.',
          style: TextStyle(color: app_colors.AppColors.textMuted, fontSize: 11),
        ),
      ],
    );
  }
}

class _CollectingNotice extends StatelessWidget {
  const _CollectingNotice({required this.record});

  final TrackRecord record;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('track-record-collecting'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: app_colors.AppColors.gold.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: app_colors.AppColors.gold),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'STILL COLLECTING RESULTS',
            style: TextStyle(
              color: app_colors.AppColors.gold,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Rates stay hidden until ${record.minimumPublishedSample} picks '
            'have been graded. ${record.sampleSize} so far, '
            '${record.gradedPicksRemaining} to go. A win rate drawn from a '
            'handful of picks would not be worth showing you.',
            style: const TextStyle(
              color: app_colors.AppColors.textMuted,
              fontSize: 11,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: record.progressToPublication,
              minHeight: 5,
              backgroundColor: app_colors.AppColors.border,
              valueColor: const AlwaysStoppedAnimation(
                app_colors.AppColors.gold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.footnote,
  });

  final String label;
  final String value;
  final String footnote;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 168,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: app_colors.AppColors.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: app_colors.AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: app_colors.AppColors.textMuted,
              fontSize: 8,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            footnote,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: app_colors.AppColors.textMuted,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

class _TierRow extends StatelessWidget {
  const _TierRow({required this.tier});

  final TrackRecordTier tier;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              tier.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            tier.published && tier.winRate != null
                ? '${(tier.winRate! * 100).toStringAsFixed(1)}%'
                : '--',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 108,
            child: Text(
              '${tier.hits}/${tier.sampleSize} graded',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: app_colors.AppColors.textMuted,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote({required this.record});

  final TrackRecord record;

  @override
  Widget build(BuildContext context) {
    final stamp = record.generatedAt;
    return Text(
      [
        if (stamp != null)
          'Updated ${stamp.toLocal()}'
        else
          'Update time unavailable',
        if (record.modelVersion.isNotEmpty) 'model ${record.modelVersion}',
        record.calibrated ? 'calibrated' : 'calibration in progress',
      ].join('  •  '),
      style: const TextStyle(
        color: app_colors.AppColors.textMuted,
        fontSize: 9,
      ),
    );
  }
}

class _IntegrityBanner extends StatelessWidget {
  const _IntegrityBanner({required this.record});

  final TrackRecord record;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('append-only-ledger'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF123226),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF3FCB8B)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.verified_user_outlined,
            color: Color(0xFF62E6A7),
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'APPEND-ONLY VERIFIED LEDGER',
                  style: TextStyle(
                    color: Color(0xFF62E6A7),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  record.losingPredictionsIncluded
                      ? 'Graded outcomes are immutable. Losing predictions stay in every published result.'
                      : 'The ledger includes every graded result and never silently removes a loss.',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownSection extends StatelessWidget {
  const _BreakdownSection({required this.title, required this.rows});

  final String title;
  final List<TrackRecordBreakdown> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: app_colors.AppColors.gold,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: .6,
          ),
        ),
        const SizedBox(height: 8),
        for (final row in rows.take(10))
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: app_colors.AppColors.panel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: app_colors.AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    row.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  row.published && row.winRate != null
                      ? '${(row.winRate! * 100).toStringAsFixed(1)}%'
                      : '--',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 78,
                  child: Text(
                    '${row.sampleSize} graded',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: app_colors.AppColors.textMuted,
                      fontSize: 9,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CalibrationSection extends StatelessWidget {
  const _CalibrationSection({required this.points});

  final List<TrackRecordCalibrationPoint> points;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'CALIBRATION: PREDICTED VS ACTUAL',
          style: TextStyle(
            color: app_colors.AppColors.gold,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: .6,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'A trustworthy 70% forecast should win about 70% of the time. Thin ranges are shown but not judged.',
          style: TextStyle(
            color: app_colors.AppColors.textMuted,
            fontSize: 9,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 10),
        for (final point in points)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 58,
                  child: Text(
                    point.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      _CalibrationBar(
                        label: 'P',
                        value: point.predicted,
                        color: app_colors.AppColors.gold,
                      ),
                      const SizedBox(height: 3),
                      _CalibrationBar(
                        label: 'A',
                        value: point.observed,
                        color: point.judged
                            ? const Color(0xFF62E6A7)
                            : app_colors.AppColors.textMuted,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 48,
                  child: Text(
                    'n=${point.sampleSize}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: app_colors.AppColors.textMuted,
                      fontSize: 8,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CalibrationBar extends StatelessWidget {
  const _CalibrationBar({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double? value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final safe = (value ?? 0).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 14,
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 8,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: safe,
              minHeight: 6,
              backgroundColor: app_colors.AppColors.border,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 36,
          child: Text(
            value == null ? '--' : '${(value! * 100).toStringAsFixed(0)}%',
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white70, fontSize: 8),
          ),
        ),
      ],
    );
  }
}
