import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receipt_tracker/state/providers.dart';
import 'package:receipt_tracker/util/budget_rules.dart';
import 'package:receipt_tracker/util/money.dart';

/// Settings. One setting so far.
///
/// Photo retention, the app lock and notification toggles land here in
/// Phase 4.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _budget = TextEditingController();

  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _budget.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final cents = parseAmountToCents(_budget.text);
    if (cents == null) return;

    setState(() => _saving = true);

    final messenger = ScaffoldMessenger.of(context);
    await ref.read(budgetRepositoryProvider).setWeeklyCents(cents);

    if (!mounted) return;
    setState(() => _saving = false);
    messenger.showSnackBar(const SnackBar(content: Text('Budget saved')));
  }

  @override
  Widget build(BuildContext context) {
    final budget = ref.watch(budgetProvider);
    final theme = Theme.of(context);

    // Seed the field once, the first time the stored budget arrives. Doing it
    // on every build would fight the user for control of the cursor.
    final current = budget.value;
    if (!_loaded && current != null) {
      _loaded = true;
      _budget.text = current.isSet
          ? formatCents(current.weeklyCents, withSymbol: false)
          : '';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text('Weekly budget', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'What you plan to spend in a week on everyday things — transit, '
              'coffee, eating out. Leave rent and other fixed monthly bills '
              'out of it; they would swamp the number.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _budget,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Amount per week',
                prefixText: r'$ ',
                border: OutlineInputBorder(),
                helperText: 'Leave at 0 for no budget',
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return 'Enter an amount, or 0 for none';
                if (parseAmountToCents(text) == null) {
                  return 'Not a valid amount';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save budget'),
            ),
            const Divider(height: 48),
            Text(
              'Warnings appear at $kApproachingPercent% of the budget and '
              'again when it is passed.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
