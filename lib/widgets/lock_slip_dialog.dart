import 'package:flutter/material.dart';

import '../models/slip_selection.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';

String normalizeSlipSite(String value) {
  final source = value.toUpperCase();
  if (source.contains('PRIZEPICKS') || source.contains('PRIZE PICKS')) {
    return 'PRIZEPICKS';
  }
  if (source.contains('UNDERDOG')) return 'UNDERDOG';
  if (source.contains('PICK6') || source.contains('PICK 6')) return 'PICK6';
  if (source.contains('FANDUEL')) return 'FANDUEL';
  if (source.contains('DRAFTKINGS')) return 'DRAFTKINGS';
  return 'PRIZEPICKS';
}

List<String> slipEntryTypesForSite(String site) => switch (site) {
  'PRIZEPICKS' => const ['POWER', 'FLEX'],
  'FANDUEL' || 'DRAFTKINGS' => const ['PARLAY'],
  _ => const ['POWER'],
};

double fixedSlipMultiplier({
  required String site,
  required String entryType,
  required int legCount,
}) {
  if (site == 'PRIZEPICKS' && entryType == 'FLEX') {
    return switch (legCount) {
      3 => 2.25,
      4 => 5,
      5 => 10,
      6 => 25,
      _ => 1,
    };
  }
  if (site == 'PRIZEPICKS') {
    return switch (legCount) {
      2 => 3,
      3 => 5,
      4 => 10,
      5 => 20,
      6 => 37.5,
      _ => 1,
    };
  }
  if (site == 'UNDERDOG') {
    return switch (legCount) {
      2 => 3,
      3 => 6,
      4 => 10,
      5 => 20,
      6 => 40,
      _ => 1,
    };
  }
  return 1;
}

class LockSlipDialog extends StatefulWidget {
  const LockSlipDialog({
    super.key,
    required this.selections,
    required this.apiService,
  });

  final List<SlipSelection> selections;
  final ApiService apiService;

  @override
  State<LockSlipDialog> createState() => _LockSlipDialogState();
}

class _LockSlipDialogState extends State<LockSlipDialog> {
  final _formKey = GlobalKey<FormState>();
  final _stakeController = TextEditingController(text: '10.00');
  String _selectedSite = 'PRIZEPICKS';
  String _entryType = 'POWER';
  bool _loadingPreview = false;
  String? _error;
  double? _potentialPayout;
  double? _potentialProfit;

  List<String> get _siteOptions {
    final options = <String>{
      for (final selection in widget.selections)
        normalizeSlipSite(
          '${selection.prop.sportsbook} ${selection.prop.sourceProvider}',
        ),
    }..removeWhere((site) => site.isEmpty);
    if (options.isEmpty) options.add('PRIZEPICKS');
    return options.toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _selectedSite = _siteOptions.first;
    _entryType = slipEntryTypesForSite(_selectedSite).first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updatePreview();
    });
  }

  @override
  void dispose() {
    _stakeController.dispose();
    super.dispose();
  }

  double? _readStake() =>
      double.tryParse(_stakeController.text.replaceAll(r'$', '').trim());

  Future<void> _updatePreview() async {
    final stake = _readStake();
    if (stake == null || stake <= 0) {
      setState(() {
        _potentialPayout = null;
        _potentialProfit = null;
      });
      return;
    }

    if (_selectedSite == 'PRIZEPICKS' || _selectedSite == 'UNDERDOG') {
      final multiplier = fixedSlipMultiplier(
        site: _selectedSite,
        entryType: _entryType,
        legCount: widget.selections.length,
      );
      setState(() {
        _loadingPreview = false;
        if (multiplier <= 1) {
          _error =
              'Selected play type is not available for ${widget.selections.length} legs.';
          _potentialPayout = null;
          _potentialProfit = null;
        } else {
          _error = null;
          _potentialPayout = stake * multiplier;
          _potentialProfit = _potentialPayout! - stake;
        }
      });
      return;
    }

    setState(() {
      _loadingPreview = true;
      _error = null;
    });
    try {
      final preview = await widget.apiService.previewSlip(
        selections: widget.selections,
        stake: stake,
      );
      if (!mounted) return;
      setState(() {
        _potentialPayout = preview['potentialPayout'];
        _potentialProfit = preview['potentialProfit'];
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loadingPreview = false);
    }
  }

  void _confirm() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(context).pop(_readStake());
    }
  }

  @override
  Widget build(BuildContext context) {
    final entryTypes = slipEntryTypesForSite(_selectedSite);
    final selectedEntryType = entryTypes.contains(_entryType)
        ? _entryType
        : entryTypes.first;
    final entryTypeLabel = switch (selectedEntryType) {
      'PARLAY' => 'Parlay',
      'POWER' => 'Power Play',
      _ => 'Flex Play',
    };

    return AlertDialog(
      backgroundColor: AppColors.panel,
      title: Row(
        children: [
          const Expanded(
            child: Text(
              'LOCK SLIP',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      content: SizedBox(
        width: 430,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.selections.length} LEG SLIP',
                style: const TextStyle(
                  color: AppColors.goldHighlight,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedSite,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Prop Site',
                  border: OutlineInputBorder(),
                ),
                items: _siteOptions
                    .map(
                      (site) =>
                          DropdownMenuItem(value: site, child: Text(site)),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedSite = value;
                    _entryType = slipEntryTypesForSite(value).first;
                  });
                  _updatePreview();
                },
              ),
              if (_selectedSite == 'PRIZEPICKS') ...[
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'POWER',
                      label: Text('POWER PLAY'),
                      icon: Icon(Icons.bolt),
                    ),
                    ButtonSegment(
                      value: 'FLEX',
                      label: Text('FLEX PLAY'),
                      icon: Icon(Icons.shield_outlined),
                    ),
                  ],
                  selected: {selectedEntryType},
                  onSelectionChanged: (selection) {
                    setState(() => _entryType = selection.first);
                    _updatePreview();
                  },
                ),
              ] else ...[
                const SizedBox(height: 12),
                Text(
                  'Entry Type: ${entryTypes.first}',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'Site: $_selectedSite \u2022 Entry: $entryTypeLabel',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('lock-slip-stake'),
                controller: _stakeController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Stake',
                  prefixText: r'$',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final stake = double.tryParse(
                    value?.replaceAll(r'$', '').trim() ?? '',
                  );
                  return stake == null || stake <= 0
                      ? r'Enter a stake greater than $0.'
                      : null;
                },
                onChanged: (_) => _updatePreview(),
              ),
              const SizedBox(height: 18),
              _PreviewRow(
                label: 'Potential payout',
                value: _potentialPayout,
                loading: _loadingPreview,
              ),
              const SizedBox(height: 8),
              _PreviewRow(
                label: 'Potential profit',
                value: _potentialProfit,
                loading: _loadingPreview,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFFF9EA6),
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          onPressed: _loadingPreview ? null : _confirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: Colors.black,
          ),
          child: const Text(
            'LOCK SLIP',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.label,
    required this.value,
    required this.loading,
  });

  final String label;
  final double? value;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
        ),
        const Spacer(),
        if (loading)
          const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.goldHighlight,
            ),
          )
        else
          Text(
            value == null ? '--' : '\$${value!.toStringAsFixed(2)}',
            style: const TextStyle(
              color: AppColors.goldHighlight,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
      ],
    );
  }
}
