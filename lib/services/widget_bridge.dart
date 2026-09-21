import 'dart:io';

import 'package:flutter/services.dart';

/// Everything the home screen widget shows, already formatted.
///
/// Strings, not numbers. Money formatting lives in `formatCents` and the
/// week label in `week_math` — pushing cents across the channel would mean a
/// second implementation of both in Kotlin, and two implementations of a
/// money format is one more than can be kept in agreement.
///
/// `percent` is the exception: a `ProgressBar` needs an integer, and clamping
/// is a display rule rather than a formatting one.
class WidgetSnapshot {
  const WidgetSnapshot({
    required this.weekLabel,
    required this.spentText,
    required this.budgetText,
    required this.statusText,
    required this.percent,
    required this.outcome,
  });

  final String weekLabel;
  final String spentText;
  final String budgetText;
  final String statusText;

  /// 0 to 100. Clamped, because a week at 340% of budget should fill the bar
  /// rather than overflow it.
  final int percent;

  /// `under`, `approaching`, `over` or `noBudget`. Kotlin uses it to pick a
  /// colour and nothing else.
  final String outcome;

  Map<String, Object?> toChannel() => <String, Object?>{
    'weekLabel': weekLabel,
    'spentText': spentText,
    'budgetText': budgetText,
    'statusText': statusText,
    'percent': percent,
    'outcome': outcome,
  };

  @override
  bool operator ==(Object other) =>
      other is WidgetSnapshot &&
      other.weekLabel == weekLabel &&
      other.spentText == spentText &&
      other.budgetText == budgetText &&
      other.statusText == statusText &&
      other.percent == percent &&
      other.outcome == outcome;

  @override
  int get hashCode => Object.hash(
    weekLabel,
    spentText,
    budgetText,
    statusText,
    percent,
    outcome,
  );
}

/// Pushes the current week to the home screen widget.
abstract interface class WidgetBridge {
  bool get isSupported;

  /// Sends a snapshot. Safe to call when no widget has been placed.
  Future<void> push(WidgetSnapshot snapshot);
}

/// The real one, over a MethodChannel to `BudgetWidgetPlugin`.
class ChannelWidgetBridge implements WidgetBridge {
  const ChannelWidgetBridge();

  /// Must match `BudgetWidgetPlugin.CHANNEL`. A plain literal on both sides,
  /// for the reasons in decision 0015.
  static const String channelName = 'receipt_tracker/widget';

  static const MethodChannel _channel = MethodChannel(channelName);

  @override
  bool get isSupported => Platform.isAndroid;

  @override
  Future<void> push(WidgetSnapshot snapshot) async {
    try {
      await _channel.invokeMethod<void>('update', snapshot.toChannel());
    } on PlatformException {
      // A widget that fails to redraw is not worth interrupting anyone over.
      // It is a convenience surface; the app itself is the source of truth.
    } on MissingPluginException {
      // Nothing registered on the other side. Same reasoning.
    }
  }
}

/// Does nothing, for platforms with no widget.
class UnavailableWidgetBridge implements WidgetBridge {
  const UnavailableWidgetBridge();

  @override
  bool get isSupported => false;

  @override
  Future<void> push(WidgetSnapshot snapshot) async {}
}
