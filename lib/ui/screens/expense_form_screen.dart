import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:receipt_tracker/models/expense.dart';
import 'package:receipt_tracker/state/providers.dart';
import 'package:receipt_tracker/util/budget_rules.dart';
import 'package:receipt_tracker/util/money.dart';
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
    _spentOn = initial?.spentOn ?? DateTime.now();
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
    final picked = await showDatePicker(
      context: context,
      initialDate: _spentOn,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
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
    final repository = ref.read(expenseRepositoryProvider);
    final note = _note.text.trim();
    final initial = widget.initial;

    try {
      if (initial == null) {
        await repository.insert(
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
        await repository.update(
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
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit expense' : 'Add expense'),
        actions: <Widget>[
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
