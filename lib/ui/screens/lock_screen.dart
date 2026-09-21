import 'package:flutter/material.dart';

/// What stands between someone holding your phone and your receipts.
///
/// Deliberately blank of content. The point of the lock is that the week's
/// spending is not readable, so this screen shows no figures, no merchant
/// names and no thumbnails — not even blurred, since a blur that can be
/// screenshotted is decoration rather than a lock.
class LockScreen extends StatelessWidget {
  const LockScreen({required this.onUnlock, required this.busy, super.key});

  final VoidCallback onUnlock;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.lock_outline,
                size: 56,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 20),
              Text('LeafLine is locked', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Unlock with your fingerprint, face or device PIN.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: busy ? null : onUnlock,
                icon: const Icon(Icons.lock_open_outlined),
                label: const Text('Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
