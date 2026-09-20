import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receipt_tracker/models/photo_retention.dart';
import 'package:receipt_tracker/state/providers.dart';
import 'package:receipt_tracker/util/budget_rules.dart';
import 'package:receipt_tracker/util/bytes.dart';
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
    // Goes through the week repository, not a separate budget one. Writing
    // the default also updates the current week when that week has not been
    // given its own figure — a second write path to the same row would skip
    // that rule and quietly desynchronise the week in progress.
    await ref.read(weekBudgetRepositoryProvider).setDefaultWeeklyCents(cents);

    if (!mounted) return;
    setState(() => _saving = false);
    messenger.showSnackBar(const SnackBar(content: Text('Budget saved')));
  }

  /// Saves the retention window and immediately applies it.
  ///
  /// Sweeping here rather than waiting for the next launch matters: someone
  /// who has just shortened the window did so because they want the space
  /// back, and an app that says "one month" while still holding a year of
  /// photos is lying about its own setting.
  Future<void> _saveRetention(PhotoRetention retention) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(settingsRepositoryProvider).setPhotoRetention(retention);
    final removed = await ref
        .read(photoRetentionSweeperProvider)
        .sweep(retention: retention, now: ref.read(nowProvider)());

    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          removed == 0
              ? 'Photos kept for ${retention.label.toLowerCase()}'
              : 'Removed ${formatPhotoCount(removed).toLowerCase()}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final budget = ref.watch(defaultBudgetProvider);
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
            Text('Default weekly budget', style: theme.textTheme.titleMedium),
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
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'What this changes',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Every new week starts from this figure, and the week '
                      'you are in now follows it too.\n\n'
                      'Weeks that have already finished keep whatever budget '
                      'they ran on. Changing this number never rewrites your '
                      'history.\n\n'
                      'To give one week its own budget — a holiday, say — open '
                      'All weeks and pick it. The week after still starts from '
                      'this default.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 40),
            Text('Receipt photos', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Photos are kept for a while and then removed. Your expenses '
              'are never touched \u2014 the amount, date and category stay '
              'forever, and only the picture ages out.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _RetentionField(onChanged: _saveRetention),
            const SizedBox(height: 12),
            const _StorageUsageRow(),
            const Divider(height: 40),
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

class _RetentionField extends ConsumerWidget {
  const _RetentionField({required this.onChanged});

  final ValueChanged<PhotoRetention> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final retention = ref.watch(photoRetentionProvider);

    return DropdownButtonFormField<PhotoRetention>(
      initialValue: retention.value ?? PhotoRetention.fallback,
      decoration: const InputDecoration(
        labelText: 'Keep photos for',
        border: OutlineInputBorder(),
      ),
      items: <DropdownMenuItem<PhotoRetention>>[
        for (final option in PhotoRetention.values)
          DropdownMenuItem<PhotoRetention>(
            value: option,
            child: Text(option.label),
          ),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class _StorageUsageRow extends ConsumerWidget {
  const _StorageUsageRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final usage = ref.watch(storageUsageProvider);
    final value = usage.value;

    return Row(
      children: <Widget>[
        Icon(
          Icons.sd_storage_outlined,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Text(
          value == null
              ? 'Checking storage\u2026'
              : '${formatPhotoCount(value.photoCount)} \u00b7 '
                    '${formatBytes(value.bytes)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
