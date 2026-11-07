import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// App animation preference, combined with the OS reduce-motion request.
class HyesMotionScope extends InheritedWidget {
  const HyesMotionScope({
    super.key, required this.enabled, required super.child,
  });
  final bool enabled;

  static bool enabledOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HyesMotionScope>()
          ?.enabled ?? true;

  @override
  bool updateShouldNotify(covariant HyesMotionScope oldWidget) =>
      oldWidget.enabled != enabled;
}

/// One animation language throughout the app. Accessibility never inherits a
/// spring/translation from a parent when reduce-motion is enabled.
abstract final class HyesMotion {
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 420);
  static const hero = Duration(milliseconds: 520);
  static const standard = Cubic(.2, 0, 0, 1);
  static const enter = Curves.easeOutCubic;
  static const emphasized = Curves.easeInOutCubicEmphasized;
  static const spring = SpringDescription(mass: 1, stiffness: 260, damping: 24);

  static bool reduced(BuildContext context) =>
      (MediaQuery.maybeOf(context)?.disableAnimations ?? false) ||
      !HyesMotionScope.enabledOf(context);

  static Duration duration(BuildContext context, Duration normal) =>
      !HyesMotionScope.enabledOf(context)
          ? Duration.zero : reduced(context) ? fast : normal;

  static void selected(BuildContext context) {
    if (!reduced(context)) HapticFeedback.selectionClick();
  }

  static void confirmed(BuildContext context) {
    if (!reduced(context)) HapticFeedback.lightImpact();
  }

  static void stamped(BuildContext context) {
    if (!reduced(context)) HapticFeedback.mediumImpact();
  }
}
