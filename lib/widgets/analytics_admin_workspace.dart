import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/analytics_page.dart';
import '../services/api_service.dart';
import '../services/auth_manager.dart';
import '../theme/app_colors.dart' as app_colors;

class AnalyticsAdminWorkspace extends StatefulWidget {
  const AnalyticsAdminWorkspace({
    super.key,
    required this.selectedSport,
    this.startInDataAdmin = false,
  });

  final String selectedSport;
  final bool startInDataAdmin;

  @override
  State<AnalyticsAdminWorkspace> createState() =>
      _AnalyticsAdminWorkspaceState();
}

class _AnalyticsAdminWorkspaceState extends State<AnalyticsAdminWorkspace> {
  late bool _showDataAdmin = widget.startInDataAdmin;

  Widget _viewButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? app_colors.AppColors.gold : Colors.white,
        backgroundColor: selected
            ? app_colors.AppColors.gold.withValues(alpha: .10)
            : app_colors.AppColors.sidebar,
        side: BorderSide(
          color: selected
              ? app_colors.AppColors.gold
              : app_colors.AppColors.border,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AuthSessionState>(
      valueListenable: AuthManager.instance.sessionState,
      builder: (context, authState, _) {
        final canUseDataAdmin = authState.isOwner;
        final showDataAdmin = canUseDataAdmin && _showDataAdmin;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
              decoration: const BoxDecoration(
                color: app_colors.AppColors.sidebar,
                border: Border(
                  bottom: BorderSide(color: app_colors.AppColors.border),
                ),
              ),
              child: Row(
                children: [
                  _viewButton(
                    label: 'ANALYTICS',
                    icon: Icons.analytics_outlined,
                    selected: !showDataAdmin,
                    onPressed: () => setState(() => _showDataAdmin = false),
                  ),
                  if (canUseDataAdmin) ...[
                    const SizedBox(width: 8),
                    _viewButton(
                      label: 'DATA ADMIN',
                      icon: Icons.admin_panel_settings_outlined,
                      selected: showDataAdmin,
                      onPressed: () => setState(() => _showDataAdmin = true),
                    ),
                  ],
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: authState.hasEdgeAccess
                          ? app_colors.AppColors.gold
                          : app_colors.AppColors.silver,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      authState.hasEdgeAccess ? 'PRO' : 'CORE',
                      style: const TextStyle(
                        color: app_colors.AppColors.bgBase,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: showDataAdmin
                  ? const DataAdminPage()
                  : AnalyticsPage(
                      selectedSport: widget.selectedSport,
                      hasProAccess: authState.hasEdgeAccess,
                    ),
            ),
          ],
        );
      },
    );
  }
}

class DataAdminPage extends StatefulWidget {
  const DataAdminPage({super.key, this.apiService});

  final ApiService? apiService;

  @override
  State<DataAdminPage> createState() => _DataAdminPageState();
}

class _DataAdminPageState extends State<DataAdminPage> {
  late final ApiService _apiService = widget.apiService ?? ApiService();
  final TextEditingController _identityController = TextEditingController();
  final TextEditingController _availabilityController = TextEditingController();

  bool _isBusy = false;
  String _identityMode = 'merge';
  String _availabilityMode = 'merge';
  String _statusText = '';
  String _unresolvedSummary = '';
  String _identityPreviewText = 'Identity preview: 0 entries';
  String _availabilityPreviewText = 'Availability preview: 0 players';
  Map<String, dynamic>? _lastUnresolvedGrouped;
  Map<String, dynamic>? _operations;
  Map<String, dynamic>? _acceptance;
  Map<String, dynamic>? _controlPanel;
  final List<String> _uploadAuditEntries = [];

  static const String _auditPrefKey = 'data_admin_upload_audit_v1';

  @override
  void initState() {
    super.initState();
    _identityController.text = const JsonEncoder.withIndent('  ').convert({
      'providers': {'odds-api': {}},
    });
    _availabilityController.text = const JsonEncoder.withIndent(
      '  ',
    ).convert({'players': {}});
    _identityController.addListener(_refreshPreviewCounts);
    _availabilityController.addListener(_refreshPreviewCounts);
    _refreshPreviewCounts();
    unawaited(_loadAuditEntries());
    unawaited(_refreshUnresolved());
    unawaited(_refreshOperations());
    unawaited(_refreshAcceptance());
    unawaited(_refreshControlPanel());
  }

  Future<void> _refreshControlPanel() async {
    try {
      final result = await _apiService.fetchLaunchControlPanel();
      if (mounted) {
        setState(() => _controlPanel = result);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _statusText = 'Launch control panel failed: $error');
      }
    }
  }

  Widget _buildLaunchControlPanel() {
    final api = _controlPanel?['api'] as Map? ?? const {};
    final redis = _controlPanel?['redis'] as Map? ?? const {};
    final workers = _controlPanel?['workers'] as Map? ?? const {};
    final providers = _controlPanel?['providers'] as Map? ?? const {};
    final freshness = _controlPanel?['propFreshness'] as Map? ?? const {};
    final scoreboard = _controlPanel?['scoreboardLatency'] as Map? ?? const {};
    final activeUsers = _controlPanel?['activeUsers'] as Map? ?? const {};
    final newSignups = _controlPanel?['newSignups'] as Map? ?? const {};
    final failedLogins = _controlPanel?['failedLogins'] as Map? ?? const {};
    final failedPayments = _controlPanel?['failedPayments'] as Map? ?? const {};
    final unsettledSlips = _controlPanel?['unsettledSlips'] as Map? ?? const {};
    final gradingReview = _controlPanel?['gradingReview'] as Map? ?? const {};
    final pipelines = _controlPanel?['pipelines'] as Map? ?? const {};

    Widget signal(
      String label,
      String value,
      IconData icon, {
      bool healthy = true,
      String? detail,
    }) {
      final color = healthy
          ? const Color(0xFF8CFFB2)
          : app_colors.AppColors.goldHighlight;
      return Container(
        width: 210,
        constraints: const BoxConstraints(minHeight: 92),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF101C28),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: color.withValues(alpha: .25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 17),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF8296AA),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (detail != null) ...[
              const SizedBox(height: 4),
              Text(
                detail,
                style: const TextStyle(color: Color(0xFF8296AA), fontSize: 9),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      );
    }

    final queueAvailable = workers['available'] == true;
    final redisAvailable = redis['available'] == true;
    final feedHealthy = freshness['healthy'] == true;
    final quotaLow = providers['lowQuota'] == true;
    final failedLoginCount = failedLogins['count'];
    final version = api['version']?.toString() ?? 'Loading';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF07121C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A3D51)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.dashboard_customize_outlined,
                color: app_colors.AppColors.gold,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'LAUNCH-DAY CONTROL PANEL',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
              IconButton(
                onPressed: _refreshControlPanel,
                tooltip: 'Refresh launch telemetry',
                icon: const Icon(
                  Icons.refresh,
                  color: Colors.white70,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              signal(
                'API HEALTH',
                api['status']?.toString().toUpperCase() ?? 'LOADING',
                Icons.cloud_done_outlined,
                healthy: api['status'] == 'ok',
              ),
              signal(
                'REDIS HEALTH',
                redisAvailable
                    ? 'CONNECTED'
                    : (redis['mode']?.toString().toUpperCase() ?? 'LOADING'),
                Icons.storage_outlined,
                healthy: redisAvailable,
              ),
              signal(
                'WORKERS / QUEUE',
                queueAvailable
                    ? '${workers['workers'] ?? 0} workers'
                    : (workers['mode']?.toString().toUpperCase() ?? 'LOADING'),
                Icons.precision_manufacturing_outlined,
                healthy: queueAvailable,
                detail:
                    '${workers['queued'] ?? 0} queued • ${workers['failed'] ?? 0} failed',
              ),
              signal(
                'PROVIDER ERRORS',
                '${providers['errors'] ?? 0}',
                Icons.report_problem_outlined,
                healthy: (providers['errors'] ?? 0) == 0,
                detail:
                    '${providers['remainingQuota'] ?? 'Unknown'} quota remaining',
              ),
              signal(
                'PROP FRESHNESS',
                freshness['ageMinutes'] == null
                    ? 'UNKNOWN'
                    : '${freshness['ageMinutes']} min old',
                Icons.update_outlined,
                healthy: feedHealthy,
                detail: '${freshness['total'] ?? 0} live props',
              ),
              signal(
                'SCOREBOARD LATENCY',
                scoreboard['lastMs'] == null
                    ? 'NOT CHECKED'
                    : '${scoreboard['lastMs']} ms',
                Icons.speed_outlined,
                healthy: scoreboard['status'] == 'ok',
                detail: 'p95 ${scoreboard['p95Ms'] ?? '—'} ms',
              ),
              signal(
                'ACTIVE USERS',
                activeUsers['count']?.toString() ?? 'UNAVAILABLE',
                Icons.people_outline,
                healthy: activeUsers['instrumented'] == true,
                detail: 'Observed in the last 15 minutes',
              ),
              signal(
                'NEW SIGNUPS',
                newSignups['count']?.toString() ?? 'UNAVAILABLE',
                Icons.person_add_alt_1_outlined,
                healthy: newSignups['instrumented'] == true,
                detail:
                    '24h • 7d ${newSignups['last7Days'] ?? '--'} • total ${newSignups['total'] ?? '--'}',
              ),
              signal(
                'FAILED LOGINS',
                failedLoginCount?.toString() ?? 'NOT INSTRUMENTED',
                Icons.no_accounts_outlined,
                healthy: failedLoginCount == 0,
                detail: 'Supabase log integration required',
              ),
              signal(
                'FAILED PAYMENTS',
                '${failedPayments['count'] ?? 'Unknown'}',
                Icons.credit_card_off_outlined,
                healthy: (failedPayments['count'] ?? 0) == 0,
                detail: 'Last 24 hours',
              ),
              signal(
                'UNSETTLED SLIPS',
                '${unsettledSlips['count'] ?? 'Unknown'}',
                Icons.receipt_long_outlined,
                detail: 'Active tickets awaiting settlement',
              ),
              signal(
                'GRADING REVIEW',
                '${gradingReview['questionableCount'] ?? 'Unknown'}',
                Icons.fact_check_outlined,
                healthy: (gradingReview['questionableCount'] ?? 0) == 0,
                detail:
                    '${gradingReview['unsettledCount'] ?? 'Unknown'} overdue pending legs',
              ),
              signal(
                'DEPLOYMENT VERSION',
                version.length > 10 ? version.substring(0, 10) : version,
                Icons.rocket_launch_outlined,
                detail: 'API release commit',
              ),
              signal(
                'PIPELINES',
                pipelines['healthy'] == true ? 'HEALTHY' : 'ATTENTION',
                Icons.account_tree_outlined,
                healthy: pipelines['healthy'] == true,
                detail:
                    '${(pipelines['activeFailures'] as List?)?.length ?? 0} active failures',
              ),
            ],
          ),
          if (quotaLow) ...[
            const SizedBox(height: 10),
            const Text(
              'Provider quota is below the configured reserve.',
              style: TextStyle(
                color: app_colors.AppColors.goldHighlight,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _refreshAcceptance() async {
    try {
      final result = await _apiService.fetchProductionAcceptance();
      if (mounted) {
        setState(() => _acceptance = result);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _statusText = 'Production health failed: $error');
      }
    }
  }

  Widget _buildAcceptancePanel() {
    final status =
        _acceptance?['status']?.toString().toUpperCase() ?? 'LOADING';
    final feed = _acceptance?['propFeed'] as Map? ?? const {};
    final billing = _acceptance?['billing'] as Map? ?? const {};
    final quota = _acceptance?['providerQuota'] as Map? ?? const {};
    final issues = _acceptance?['issues'] as List? ?? const [];
    final color = status == 'HEALTHY'
        ? const Color(0xFF8CFFB2)
        : status == 'WARNING'
        ? app_colors.AppColors.goldHighlight
        : const Color(0xFFFF8A80);
    Widget metric(String label, String value, IconData icon) => Container(
      width: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF101C28),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: app_colors.AppColors.gold, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF8296AA),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF07121C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_outlined, color: color, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'PRODUCTION ACCEPTANCE',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
              Text(
                status,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              IconButton(
                onPressed: _refreshAcceptance,
                tooltip: 'Refresh production health',
                icon: const Icon(
                  Icons.refresh,
                  color: Colors.white70,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              metric(
                'LIVE PROPS',
                '${feed['total'] ?? 0}',
                Icons.analytics_outlined,
              ),
              metric(
                'FEED AGE',
                feed['ageMinutes'] == null
                    ? 'Unknown'
                    : '${feed['ageMinutes']} min',
                Icons.schedule,
              ),
              metric(
                'ODDS QUOTA',
                '${quota['remaining'] ?? 'Unknown'} remaining',
                Icons.speed,
              ),
              metric(
                'BILLING',
                billing['webhookConfigured'] == true &&
                        billing['coreProductsConfigured'] == true &&
                        billing['edgeProductsConfigured'] == true
                    ? 'Configured'
                    : 'Needs attention',
                Icons.payments_outlined,
              ),
            ],
          ),
          if (issues.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...issues.whereType<Map>().map(
              (issue) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '• ${issue['message']}',
                  style: TextStyle(
                    color: issue['severity'] == 'critical'
                        ? const Color(0xFFFF8A80)
                        : app_colors.AppColors.goldHighlight,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'Webhook delivery is only marked verified after a successful test or purchase event.',
            style: TextStyle(color: Color(0xFF8296AA), fontSize: 10),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshOperations() async {
    try {
      final result = await _apiService.fetchAdminOperations();
      if (mounted) {
        setState(() => _operations = result);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _statusText = 'Pipeline monitoring failed: $error');
      }
    }
  }

  Widget _buildOperationsPanel() {
    final runs = _operations?['runs'] as List? ?? const [];
    final latest = runs.isNotEmpty && runs.first is Map
        ? runs.first as Map
        : null;
    final valid =
        (_operations?['validCalibrationResults'] as num?)?.toInt() ?? 0;
    final pending = (_operations?['pendingPredictions'] as num?)?.toInt() ?? 0;
    final status = latest?['status']?.toString() ?? 'NO RUNS';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: app_colors.AppColors.sidebar,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2A3D51)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.monitor_heart_outlined,
            color: app_colors.AppColors.gold,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            'PIPELINE $status',
            style: TextStyle(
              color: status == 'FAILED'
                  ? const Color(0xFFFF8A80)
                  : const Color(0xFF8CFFB2),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 18),
          Text(
            'Today: ${_operations?['snapshotsToday'] ?? 0} snapshots',
            style: const TextStyle(
              color: app_colors.AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 18),
          Text(
            'Pending: $pending',
            style: const TextStyle(
              color: app_colors.AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 18),
          Text(
            'Calibration: $valid / 100',
            style: const TextStyle(
              color: app_colors.AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _refreshOperations,
            tooltip: 'Refresh pipeline status',
            icon: const Icon(Icons.refresh, color: Colors.white70, size: 18),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _identityController.removeListener(_refreshPreviewCounts);
    _availabilityController.removeListener(_refreshPreviewCounts);
    _identityController.dispose();
    _availabilityController.dispose();
    super.dispose();
  }

  void _refreshPreviewCounts() {
    final identityText = _buildIdentityPreview(_identityController.text);
    final availabilityText = _buildAvailabilityPreview(
      _availabilityController.text,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _identityPreviewText = identityText;
      _availabilityPreviewText = availabilityText;
    });
  }

  Future<void> _loadAuditEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_auditPrefKey) ?? <String>[];
    if (!mounted) {
      return;
    }
    setState(() {
      _uploadAuditEntries
        ..clear()
        ..addAll(saved);
    });
  }

  Future<void> _appendAuditEntry(String message) async {
    final timestamp = DateTime.now().toIso8601String();
    final entry = '$timestamp | $message';

    if (mounted) {
      setState(() {
        _uploadAuditEntries.insert(0, entry);
        if (_uploadAuditEntries.length > 30) {
          _uploadAuditEntries.removeRange(30, _uploadAuditEntries.length);
        }
      });
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_auditPrefKey, _uploadAuditEntries);
  }

  Future<void> _exportUnresolvedGroupedJson() async {
    setState(() {
      _isBusy = true;
      _statusText = '';
    });

    try {
      final grouped =
          _lastUnresolvedGrouped ??
          await _apiService.fetchIdentityUnresolvedGrouped();
      final count = (grouped['count'] as num?)?.toInt() ?? 0;
      final payload = const JsonEncoder.withIndent('  ').convert(grouped);

      final savePath = await FilePicker.saveFile(
        dialogTitle: 'Save unresolved grouped export',
        fileName: 'identity_unresolved_grouped.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: Uint8List.fromList(utf8.encode(payload)),
      );

      if (savePath == null || savePath.trim().isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() {
          _statusText = 'Export canceled.';
        });
        return;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _statusText = 'Exported unresolved JSON to $savePath';
      });
      await _appendAuditEntry(
        'unresolved export saved | count=$count | path=$savePath',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusText = 'Unresolved export failed: $error';
      });
      await _appendAuditEntry('unresolved export failed | $error');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _copyUnresolvedGroupedJson() async {
    try {
      final grouped =
          _lastUnresolvedGrouped ??
          await _apiService.fetchIdentityUnresolvedGrouped();
      final count = (grouped['count'] as num?)?.toInt() ?? 0;
      final payload = const JsonEncoder.withIndent('  ').convert(grouped);
      await Clipboard.setData(ClipboardData(text: payload));
      if (!mounted) {
        return;
      }
      setState(() {
        _statusText = 'Unresolved JSON copied to clipboard.';
      });
      await _appendAuditEntry('unresolved export copied | count=$count');
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusText = 'Copy unresolved JSON failed: $error';
      });
      await _appendAuditEntry('unresolved copy failed | $error');
    }
  }

  Widget _buildAuditLogPanel() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 90, maxHeight: 140),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: app_colors.AppColors.sidebar,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2A3D51)),
      ),
      child: _uploadAuditEntries.isEmpty
          ? const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'No upload audit entries yet.',
                style: TextStyle(
                  color: app_colors.AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : ListView.builder(
              itemCount: _uploadAuditEntries.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    _uploadAuditEntries[index],
                    style: const TextStyle(
                      color: app_colors.AppColors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              },
            ),
    );
  }

  String _buildIdentityPreview(String rawJson) {
    try {
      final parsed = jsonDecode(rawJson);
      if (parsed is! Map<String, dynamic>) {
        return 'Identity preview: invalid JSON object';
      }
      final providers = parsed['providers'];
      if (providers is! Map<String, dynamic>) {
        return "Identity preview: missing 'providers' object";
      }
      int entries = 0;
      for (final value in providers.values) {
        if (value is Map<String, dynamic>) {
          entries += value.length;
        }
      }
      return 'Identity preview: $entries entries across ${providers.length} providers';
    } catch (_) {
      return 'Identity preview: invalid JSON syntax';
    }
  }

  String _buildAvailabilityPreview(String rawJson) {
    try {
      final parsed = jsonDecode(rawJson);
      if (parsed is! Map<String, dynamic>) {
        return 'Availability preview: invalid JSON object';
      }
      final players = parsed['players'];
      if (players is! Map<String, dynamic>) {
        return "Availability preview: missing 'players' object";
      }
      return 'Availability preview: ${players.length} players';
    } catch (_) {
      return 'Availability preview: invalid JSON syntax';
    }
  }

  Widget _previewBadge({required String text}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: app_colors.AppColors.sidebar,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF2A3D51)),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: app_colors.AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Future<void> _refreshUnresolved() async {
    setState(() {
      _isBusy = true;
      _statusText = '';
    });
    try {
      final grouped = await _apiService.fetchIdentityUnresolvedGrouped();
      final count = (grouped['count'] as num?)?.toInt() ?? 0;
      final sportsMap = grouped['sports'];
      final sportNames = <String>[];
      if (sportsMap is Map<String, dynamic>) {
        sportNames.addAll(sportsMap.keys);
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _lastUnresolvedGrouped = grouped;
        _unresolvedSummary =
            'Unresolved players: $count (${sportNames.join(', ')})';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _unresolvedSummary = 'Unable to fetch unresolved identities: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _uploadIdentityPayload() async {
    setState(() {
      _isBusy = true;
      _statusText = '';
    });
    try {
      final parsed = jsonDecode(_identityController.text);
      if (parsed is! Map<String, dynamic>) {
        throw const FormatException('Identity payload must be a JSON object.');
      }
      final providers = parsed['providers'];
      if (providers is! Map<String, dynamic>) {
        throw const FormatException(
          "Identity payload must include top-level 'providers' object.",
        );
      }
      final result = await _apiService.bulkUpsertIdentityMap(
        payload: parsed,
        mode: _identityMode,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _statusText =
            'Identity upload complete. Provider sizes: ${result['providerSizes']}';
      });
      await _appendAuditEntry(
        'identity upload success | mode=$_identityMode | processed=${result['processedEntries'] ?? '?'}',
      );
      await _refreshUnresolved();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusText = 'Identity upload failed: $error';
      });
      await _appendAuditEntry(
        'identity upload failed | mode=$_identityMode | $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  void _validateJsonPayload({
    required TextEditingController controller,
    required String label,
    required String requiredTopLevelKey,
  }) {
    try {
      final parsed = jsonDecode(controller.text);
      if (parsed is! Map<String, dynamic>) {
        throw const FormatException('Payload root must be a JSON object.');
      }
      final topLevel = parsed[requiredTopLevelKey];
      if (topLevel is! Map<String, dynamic>) {
        throw FormatException(
          "Payload must include top-level '$requiredTopLevelKey' object.",
        );
      }
      setState(() {
        _statusText = '$label JSON is valid.';
      });
    } catch (error) {
      setState(() {
        _statusText = '$label JSON validation failed: $error';
      });
    }
  }

  Future<void> _loadPayloadFromFile({
    required TextEditingController controller,
    required String label,
    required String requiredTopLevelKey,
  }) async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (picked == null || picked.files.isEmpty) {
        return;
      }

      final selected = picked.files.first;
      final content = utf8.decode(await selected.readAsBytes());

      if (content.trim().isEmpty) {
        throw const FormatException('Selected file is empty or unreadable.');
      }

      final parsed = jsonDecode(content);
      if (parsed is! Map<String, dynamic>) {
        throw const FormatException('Payload root must be a JSON object.');
      }
      final topLevel = parsed[requiredTopLevelKey];
      if (topLevel is! Map<String, dynamic>) {
        throw FormatException(
          "Payload must include top-level '$requiredTopLevelKey' object.",
        );
      }

      if (!mounted) {
        return;
      }
      setState(() {
        controller.text = const JsonEncoder.withIndent('  ').convert(parsed);
        _statusText = '$label file loaded and validated.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusText = '$label load failed: $error';
      });
    }
  }

  Future<void> _uploadAvailabilityPayload() async {
    setState(() {
      _isBusy = true;
      _statusText = '';
    });
    try {
      final parsed = jsonDecode(_availabilityController.text);
      if (parsed is! Map<String, dynamic>) {
        throw const FormatException(
          'Availability payload must be a JSON object.',
        );
      }
      final players = parsed['players'];
      if (players is! Map<String, dynamic>) {
        throw const FormatException(
          "Availability payload must include top-level 'players' object.",
        );
      }
      final result = await _apiService.bulkUpsertPlayerAvailability(
        payload: parsed,
        mode: _availabilityMode,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _statusText = 'Availability upload complete. Count: ${result['count']}';
      });
      await _appendAuditEntry(
        'availability upload success | mode=$_availabilityMode | processed=${result['processedEntries'] ?? '?'}',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusText = 'Availability upload failed: $error';
      });
      await _appendAuditEntry(
        'availability upload failed | mode=$_availabilityMode | $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Widget _modeDropdown({
    required String label,
    required String value,
    required ValueChanged<String?> onChanged,
  }) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: app_colors.AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        DropdownButton<String>(
          value: value,
          dropdownColor: app_colors.AppColors.sidebar,
          style: const TextStyle(color: Colors.white),
          underline: Container(
            height: 1,
            color: app_colors.AppColors.chromeShadow,
          ),
          items: const [
            DropdownMenuItem(value: 'merge', child: Text('merge')),
            DropdownMenuItem(value: 'replace', child: Text('replace')),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _jsonEditor({
    required String title,
    required String schemaHint,
    required TextEditingController controller,
    required VoidCallback onUpload,
    required VoidCallback onValidate,
    required VoidCallback onLoadFile,
    required String mode,
    required ValueChanged<String?> onModeChanged,
  }) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: app_colors.AppColors.sidebar,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: app_colors.AppColors.chromeShadow),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: app_colors.AppColors.gold,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        schemaHint,
                        style: const TextStyle(
                          color: app_colors.AppColors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                _modeDropdown(
                  label: 'Mode',
                  value: mode,
                  onChanged: onModeChanged,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: TextField(
                controller: controller,
                maxLines: null,
                expands: true,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontFamily: 'Consolas',
                ),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.all(10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: app_colors.AppColors.chromeShadow,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: app_colors.AppColors.chromeShadow,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: app_colors.AppColors.gold,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton(
                  onPressed: _isBusy ? null : onLoadFile,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF3A5167)),
                  ),
                  child: const Text('Load File'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _isBusy ? null : onValidate,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF8CFFB2),
                    side: const BorderSide(color: Color(0xFF2B7A4B)),
                  ),
                  child: const Text('Validate'),
                ),
                const SizedBox(height: 4),
                ElevatedButton(
                  onPressed: _isBusy ? null : onUpload,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: app_colors.AppColors.gold,
                    foregroundColor: const Color(0xFF07131F),
                  ),
                  child: const Text('Upload JSON'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'DATA ADMIN',
                style: TextStyle(
                  color: app_colors.AppColors.gold,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 14),
              ElevatedButton(
                onPressed: _isBusy ? null : _refreshUnresolved,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1D3144),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Refresh Unresolved'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _isBusy
                    ? null
                    : () => unawaited(_exportUnresolvedGroupedJson()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF3A5167)),
                ),
                child: const Text('Export Unresolved JSON'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _isBusy
                    ? null
                    : () => unawaited(_copyUnresolvedGroupedJson()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF8CFFB2),
                  side: const BorderSide(color: Color(0xFF2B7A4B)),
                ),
                child: const Text('Copy Unresolved JSON'),
              ),
              if (_isBusy) ...[
                const SizedBox(width: 10),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          _buildLaunchControlPanel(),
          const SizedBox(height: 8),
          _buildOperationsPanel(),
          const SizedBox(height: 8),
          _buildAcceptancePanel(),
          const SizedBox(height: 8),
          Text(
            _unresolvedSummary,
            style: const TextStyle(
              color: app_colors.AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _statusText,
            style: TextStyle(
              color: _statusText.toLowerCase().contains('failed')
                  ? const Color(0xFFFF8A80)
                  : const Color(0xFF8CFFB2),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _previewBadge(text: _identityPreviewText),
              const SizedBox(width: 10),
              _previewBadge(text: _availabilityPreviewText),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Upload Audit Log',
            style: TextStyle(
              color: app_colors.AppColors.gold,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          _buildAuditLogPanel(),
          const SizedBox(height: 12),
          SizedBox(
            height: 520,
            child: Row(
              children: [
                _jsonEditor(
                  title: 'Identity Bulk Payload',
                  schemaHint:
                      'Expected: providers -> odds-api -> {source_player_id: {...}}',
                  controller: _identityController,
                  onUpload: _uploadIdentityPayload,
                  onValidate: () {
                    _validateJsonPayload(
                      controller: _identityController,
                      label: 'Identity',
                      requiredTopLevelKey: 'providers',
                    );
                  },
                  onLoadFile: () {
                    unawaited(
                      _loadPayloadFromFile(
                        controller: _identityController,
                        label: 'Identity',
                        requiredTopLevelKey: 'providers',
                      ),
                    );
                  },
                  mode: _identityMode,
                  onModeChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _identityMode = value;
                    });
                  },
                ),
                const SizedBox(width: 12),
                _jsonEditor(
                  title: 'Availability Bulk Payload',
                  schemaHint: 'Expected: players -> {canonical_player: {...}}',
                  controller: _availabilityController,
                  onUpload: _uploadAvailabilityPayload,
                  onValidate: () {
                    _validateJsonPayload(
                      controller: _availabilityController,
                      label: 'Availability',
                      requiredTopLevelKey: 'players',
                    );
                  },
                  onLoadFile: () {
                    unawaited(
                      _loadPayloadFromFile(
                        controller: _availabilityController,
                        label: 'Availability',
                        requiredTopLevelKey: 'players',
                      ),
                    );
                  },
                  mode: _availabilityMode,
                  onModeChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _availabilityMode = value;
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
