import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:receipt_tracker/state/providers.dart';
import 'package:receipt_tracker/util/money.dart';
import 'package:receipt_tracker/util/week_math.dart';

/// Sets the budget for one week specifically.
///
/// This is the vacation-week control: give a single week its own figure
/// without disturbing the standing default, so the week after it starts from
/// the usual number again.
class WeekBudgetSheet extends ConsumerStatefulWidget {
  const WeekBudgetSheet({
    required this.weekStart,
    required this.currentCents,
    required this.isOverride,
    super.key,
  });

  /// Opens the sheet and resolves once it closes.
  static Future<void> show(
    BuildContext context, {
    required DateTime weekStart,
    required int currentCents,
    required bool isOverride,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: WeekBudgetSheet(
          weekStart: weekStart,
          currentCents: currentCents,
          isOverride: isOverride,
        ),
      ),
    );
  }

  final DateTime weekStart;

  /// The figure this week runs on today, whether its own or inherited.
  final int currentCents;

  /// Whether that figure was set for this week specifically.
  final bool isOverride;

  @override
  ConsumerState<WeekBudgetSheet> createState() => _WeekBudgetSheetState();
}

class _WeekBudgetSheetState extends ConsumerState<WeekBudgetSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.currentCents > 0
          ? formatCents(widget.currentCents, withSymbol: false)
          : '',
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final cents = parseAmountToCents(_amount.text);
    if (cents == null) return;

    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    await ref
        .read(weekBudgetRepositoryProvider)
        .overrideWeek(widget.weekStart, cents);
    navigator.pop();
  }

  Future<void> _useDefault() async {
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    await ref
        .read(weekBudgetRepositoryProvider)
        .clearOverride(widget.weekStart);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final format = DateFormat.MMMd();
    final range =
        '${format.format(widget.weekStart)} \u2013 '
        '${format.format(weekEnd(widget.weekStart))}';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('Budget for $range', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                widget.isOverride
                    ? 'This week has its own budget.'
                    : 'This week follows your default budget.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Budget for this week',
                  prefixText: r'$ ',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Enter an amount';
                  if (parseAmountToCents(text) == null) {
                    return 'Not a valid amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Only this week changes. Later weeks keep using your default.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('Set for this week'),
              ),
              if (widget.isOverride) ...<Widget>[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _saving ? null : _useDefault,
                  child: const Text('Use my default instead'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
