import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:receipt_tracker/models/expense.dart';
import 'package:receipt_tracker/models/ocr_block.dart';
import 'package:receipt_tracker/services/ocr_service.dart';
import 'package:receipt_tracker/services/photo_source.dart';
import 'package:receipt_tracker/services/total_extractor.dart';
import 'package:receipt_tracker/state/providers.dart';
import 'package:receipt_tracker/ui/widgets/amount_chips.dart';
import 'package:receipt_tracker/ui/widgets/receipt_photo.dart';
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

  /// The id this expense will have.
  ///
  /// Generated up front rather than at save time, because a photo has to be
  /// filed under it the moment it is taken — well before the row exists. A
  /// photo taken and then abandoned leaves a file with no row, which is
  /// precisely what the orphan sweep is for.
  late final String _id;

  String? _photoFile;
  bool _photoBusy = false;

  /// Amounts read off the receipt, best first. Empty is the ordinary case.
  List<AmountCandidate> _candidates = const <AmountCandidate>[];

  /// Everything the recogniser saw, kept on the expense.
  ///
  /// This is what turns a receipt that fools the extractor into a fixture:
  /// read it back off the row, paste the lines into `receiptFixtures`, and
  /// the heuristic improves precisely where it failed.
  String? _ocrRawText;

  bool _ocrRunning = false;

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
    _id = initial?.id ?? const Uuid().v4();
    _photoFile = initial?.photoFile;
    _ocrRawText = initial?.ocrRawText;
  }

  /// Reads the receipt and offers what it finds.
  ///
  /// Every failure path here ends the same way: no chips. Recognition that
  /// finds nothing, a platform with no OCR, an unregistered channel and a
  /// photo of a blank wall are indistinguishable from the form's point of
  /// view, and should be — in all four cases you type the amount, which was
  /// always an option.
  Future<void> _readReceipt(String filename) async {
    final ocr = ref.read(ocrServiceProvider);
    if (!ocr.isAvailable) return;

    final store = ref.read(imageStoreProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _ocrRunning = true;
      _candidates = const <AmountCandidate>[];
    });

    try {
      final blocks = await ocr.recognize(store.fileFor(filename).path);
      if (!mounted) return;
      setState(() {
        _candidates = TotalExtractor.extract(blocks);
        _ocrRawText = blocks.isEmpty
            ? null
            : groupIntoLines(blocks).map((line) => line.text).join('\n');
      });
      if (blocks.isEmpty) {
        _report(messenger, 'read the photo but found no text');
      }
    } on OcrFailure catch (failure) {
      _report(messenger, failure.message ?? failure.kind.name);
    } finally {
      if (mounted) setState(() => _ocrRunning = false);
    }
  }

  /// Says what went wrong, in debug builds only.
  ///
  /// Release stays silent on purpose: someone standing at a till with a
  /// receipt can do nothing useful with "no plugin is registered on
  /// receipt_tracker/ocr", and the amount field was always the primary path.
  ///
  /// But silence is also how a channel that was never wired up goes
  /// unnoticed, because an unregistered plugin and an unreadable receipt look
  /// identical from here. So in debug the reason is shown.
  void _report(ScaffoldMessengerState messenger, String reason) {
    if (!kDebugMode) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('OCR: $reason'),
          duration: const Duration(seconds: 6),
        ),
      );
  }

  Future<void> _addPhoto({required bool fromGallery}) async {
    final source = ref.read(photoSourceProvider);
    if (!source.isAvailable) return;

    final messenger = ScaffoldMessenger.of(context);
    final store = ref.read(imageStoreProvider);
    setState(() => _photoBusy = true);

    try {
      final captured = fromGallery
          ? await source.pick()
          : await source.capture();
      if (captured == null) return;

      final filename = await store.save(_id, captured.bytes);
      if (!mounted) return;
      setState(() => _photoFile = filename);
      await _readReceipt(filename);
    } on PhotoFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.userMessage)));
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _removePhoto() async {
    final filename = _photoFile;
    if (filename == null) return;

    setState(() {
      _photoFile = null;
      _candidates = const <AmountCandidate>[];
      _ocrRawText = null;
    });
    // The file goes too, but only because the user asked. Deleting on expense
    // deletion would be wrong — undo re-inserts the row, and it would come
    // back pointing at a photo that no longer exists.
    await ref.read(imageStoreProvider).delete(filename);
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
      // The week comes from _spentOn, so `now` only stamps the row. Passed
      // anyway: every clock-dependent call going through nowProvider is what
      // makes "did this use the real clock?" a question nobody has to ask.
      await weeks.ensureWeek(_spentOn, now: ref.read(nowProvider)());

      if (initial == null) {
        await expenses.insert(
          Expense.create(
            id: _id,
            amountCents: cents,
            spentOn: _spentOn,
            merchant: _merchant.text.trim(),
            category: _category,
            note: note.isEmpty ? null : note,
            photoFile: _photoFile,
            ocrRawText: _ocrRawText,
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
            photoFile: _photoFile,
            clearPhoto: _photoFile == null,
            ocrRawText: _ocrRawText,
            clearOcrText: _ocrRawText == null,
          ),
        );
      }

      // After the write, never before: the alert is about what the total now
      // is. Deliberately not awaited against the pop — a notification the
      // system will deliver in its own time should not hold the screen open.
      unawaited(
        ref
            .read(budgetAlertServiceProvider)
            .checkAndNotify(now: ref.read(nowProvider)()),
      );

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

    setState(() => _saving = true);

    // Captured before the pop, because afterwards this screen's context is
    // gone. The messenger belongs to the MaterialApp rather than to this
    // route, so the snackbar lands on the list underneath.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(expenseRepositoryProvider);

    await repository.delete(initial.id);
    navigator.pop();

    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: const Text('Expense deleted'),
          action: SnackBarAction(
            label: 'Undo',
            // Re-inserting `initial` restores the expense exactly as it was
            // when this screen opened — id, timestamps and photo reference
            // included. Any unsaved edits on screen were never committed, so
            // there is nothing of them to lose.
            onPressed: () async {
              await repository.insert(initial);
            },
          ),
        ),
      );
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
            AmountChips(
              candidates: _candidates,
              running: _ocrRunning,
              onSelected: (candidate) {
                _amount.text = formatCents(candidate.cents, withSymbol: false);
                _formKey.currentState?.validate();
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
            if (ref.read(photoSourceProvider).isAvailable)
              ReceiptPhotoField(
                photoFile: _photoFile,
                busy: _photoBusy,
                onCapture: () => _addPhoto(fromGallery: false),
                onPickFromGallery: () => _addPhoto(fromGallery: true),
                onRemove: _removePhoto,
              ),
            if (ref.read(photoSourceProvider).isAvailable)
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
