import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:receipt_tracker/models/expense.dart';
import 'package:receipt_tracker/state/providers.dart';
import 'package:receipt_tracker/util/budget_rules.dart';
import 'package:receipt_tracker/util/money.dart';
import 'package:receipt_tracker/util/week_math.dart';
import 'package:uuid/uuid.dart';

/// Adds a new expense, or edits an existing one when [initial] is supplied.
///
/// One screen, no wizard. Amount is the only required field and is focused on
/// open — someone who types `12.40` and hits save has logged a valid expense.
class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen({this.initial, super.key});

  final Expense? initial;

  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _amount;
  late final TextEditingController _merchant;
  late final TextEditingController _note;

  late DateTime _spentOn;
  late ExpenseCategory _category;
  bool _saving = false;

  bool get _isEditing => widget.initial != null;

  /// True when the chosen date has moved the expense out of the week it was
  /// filed under.
  ///
  /// Without surfacing this, correcting a date makes the expense disappear
  /// from where the user was looking and reappear further down the list, with
  /// two week totals silently changing on the way.
  bool get _movesToAnotherWeek {
    final initial = widget.initial;
    if (initial == null) return false;
    return weekStart(_spentOn) != weekStart(initial.spentOn);
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _amount = TextEditingController(
      text: initial == null
          ? ''
          : formatCents(initial.amountCents, withSymbol: false),
    );
    _merchant = TextEditingController(text: initial?.merchant ?? '');
    _note = TextEditingController(text: initial?.note ?? '');
    _spentOn = initial?.spentOn ?? ref.read(nowProvider)();
    _category = initial?.category ?? ExpenseCategory.custom;
  }

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = ref.read(nowProvider)();
    // Today, not a year out. A future-dated expense would create a week
    // sitting above the current one in the list, which is not something
    // anyone wants to open their app to.
    final today = DateTime(now.year, now.month, now.day);
    // Clamped, because showDatePicker asserts when initialDate falls outside
    // the range. An expense already dated ahead — written before this cap
    // existed — would otherwise crash the picker instead of being editable.
    final start = _spentOn.isAfter(today) ? today : _spentOn;

    final picked = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime(2020),
      lastDate: today,
    );
    if (!mounted || picked == null) return;
    setState(() => _spentOn = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final cents = parseAmountToCents(_amount.text);
    if (cents == null) return;

    setState(() => _saving = true);

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final expenses = ref.read(expenseRepositoryProvider);
    final weeks = ref.read(weekBudgetRepositoryProvider);
    final note = _note.text.trim();
    final initial = widget.initial;
    final moved = _movesToAnotherWeek;
    final movedTo = weekStart(_spentOn);

    try {
      // The week has to exist before an expense can belong to it. Backdating
      // into an untracked week materialises that week at the current default,
      // which is the best answer available — there is no record of what the
      // budget was at the time.
      await weeks.ensureWeek(_spentOn);

      if (initial == null) {
        await expenses.insert(
          Expense.create(
            id: const Uuid().v4(),
            amountCents: cents,
            spentOn: _spentOn,
            merchant: _merchant.text.trim(),
            category: _category,
            note: note.isEmpty ? null : note,
          ),
        );
      } else {
        await expenses.update(
          initial.copyWith(
            amountCents: cents,
            spentOn: _spentOn,
            merchant: _merchant.text.trim(),
            category: _category,
            note: note.isEmpty ? null : note,
            clearNote: note.isEmpty,
          ),
        );
      }

      navigator.pop();

      if (moved) {
        messenger
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                'Moved to the week of ${DateFormat.MMMd().format(movedTo)}',
              ),
            ),
          );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $error')));
    }
  }

  Future<void> _delete() async {
    final initial = widget.initial;
    if (initial == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this expense?'),
        content: const Text('This cannot be undone from here.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    await ref.read(expenseRepositoryProvider).delete(initial.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit expense' : 'Add expense'),
        actions: <Widget>[
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete expense',
              onPressed: _saving ? null : _delete,
            ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            TextFormField(
              controller: _amount,
              autofocus: !_isEditing,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Amount',
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
            const SizedBox(height: 16),
            TextFormField(
              controller: _merchant,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Merchant (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _DateField(value: _spentOn, onTap: _pickDate),
            if (_movesToAnotherWeek)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.swap_horiz,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Saving moves this expense to the week of '
                        '${DateFormat.MMMd().format(weekStart(_spentOn))}, '
                        'so both weeks\u2019 totals will change.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ExpenseCategory>(
              initialValue: _category,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<ExpenseCategory>>[
                for (final category in ExpenseCategory.values)
                  DropdownMenuItem<ExpenseCategory>(
                    value: category,
                    child: Text(category.label),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _category = value);
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_isEditing ? 'Save changes' : 'Add expense'),
            ),
            if (_isEditing) ...<Widget>[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _saving ? null : _delete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete expense'),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.value, required this.onTap});

  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Date',
          border: OutlineInputBorder(),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(DateFormat.yMMMEd().format(value)),
            const Icon(Icons.calendar_today_outlined, size: 18),
          ],
        ),
      ),
    );
  }
}
