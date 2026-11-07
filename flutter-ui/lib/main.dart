import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/library_repository.dart';
import 'design/motion.dart';
import 'ui/app_shell.dart';
import 'ui/app_language.dart';
import 'ui/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Best-effort only. The OS can reject the preferred refresh rate or switch
  // dynamically for thermal and power constraints. Never block app startup.
  if (Platform.isAndroid) {
    unawaited(_requestHighRefreshRate());
  }
  runApp(const HyesReadFlutter());
}

Future<void> _requestHighRefreshRate() async {
  try {
    await FlutterDisplayMode.setHighRefreshRate();
  } catch (_) {
    // Keep the original Android-selected display mode on unsupported panels.
  }
}

class HyesReadFlutter extends StatefulWidget {
  const HyesReadFlutter({super.key});

  @override
  State<HyesReadFlutter> createState() => _HyesReadFlutterState();
}

class _HyesReadFlutterState extends State<HyesReadFlutter>
    with SingleTickerProviderStateMixin {
  final LibraryRepository repository = LibraryRepository();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey _themeCaptureKey = GlobalKey();
  AnimationController? _revealController;
  OverlayEntry? _revealEntry;
  ui.Image? _oldThemeImage;
  ThemeMode mode = ThemeMode.dark;
  HyesLanguage language = HyesLanguage.chinese;
  bool animationsEnabled = true;
  late final Future<void> startup;

  @override
  void initState() {
    super.initState();
    startup = _initialize();
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    mode = switch (prefs.getString('theme')) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    language = HyesLanguagePreference.read(prefs);
    animationsEnabled = prefs.getBool('hyes.ui.animations') ?? true;
    await repository.load();
    if (mounted) setState(() {});
  }

  Future<void> _updateMode(ThemeMode next) async {
    setState(() => mode = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', next.name);
  }

  Future<void> _updateLanguage(HyesLanguage next) async {
    if (next == language) return;
    setState(() => language = next);
    final prefs = await SharedPreferences.getInstance();
    await HyesLanguagePreference.save(prefs, next);
  }

  Future<void> _updateAnimationsEnabled(bool enabled) async {
    if (animationsEnabled == enabled) return;
    setState(() => animationsEnabled = enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hyes.ui.animations', enabled);
  }

  /// A light-to-dark circular reveal inspired by Flutter Vignettes. The old
  /// rendered frame masks the new theme; no ongoing BackdropFilter is retained.
  Future<void> _updateModeAt(ThemeMode next, Offset origin) async {
    if (!mounted || next == mode) return;
    final captureContext = _themeCaptureKey.currentContext;
    if (captureContext == null || HyesMotion.reduced(captureContext)) {
      await _updateMode(next);
      return;
    }
    ui.Image? oldFrame;
    try {
      final boundary = captureContext.findRenderObject();
      if (boundary is RenderRepaintBoundary && !boundary.debugNeedsPaint) {
        oldFrame = await boundary.toImage(pixelRatio:
          math.min(MediaQuery.devicePixelRatioOf(captureContext), 2.0));
      }
    } catch (_) {
      // Snapshot errors never block a real theme preference change.
    }
    if (!mounted) {
      oldFrame?.dispose();
      return;
    }
    _clearThemeReveal();
    setState(() => mode = next);
    if (oldFrame != null) {
      final image = oldFrame;
      _oldThemeImage = image;
      final controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
      _revealController = controller;
      final entry = OverlayEntry(builder: (context) =>
        Positioned.fill(child: IgnorePointer(child: AnimatedBuilder(
          animation: controller,
          builder: (_, _) => CustomPaint(painter: _PaperThemeReveal(
            oldFrame: image,
            origin: origin,
            fraction: HyesMotion.emphasized.transform(controller.value))),
        ))));
      _revealEntry = entry;
      final overlay = _navigatorKey.currentState?.overlay;
      if (overlay == null) {
        _clearThemeReveal();
      } else {
        overlay.insert(entry);
        controller.addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _revealController == controller) {
                _clearThemeReveal();
              }
            });
          }
        });
        controller.forward();
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', next.name);
  }

  void _clearThemeReveal() {
    _revealEntry?.remove();
    _revealEntry?.dispose();
    _revealEntry = null;
    _revealController?.dispose();
    _revealController = null;
    _oldThemeImage?.dispose();
    _oldThemeImage = null;
  }

  @override
  void dispose() {
    _clearThemeReveal();
    repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      builder: (context, child) => HyesMotionScope(
        enabled: animationsEnabled,
        child: HyesLanguageScope(
          language: language,
          child: RepaintBoundary(key: _themeCaptureKey, child: child!))),
      title: 'HyesRead',
      debugShowCheckedModeBanner: false,
      theme: hyesReadTheme(Brightness.light),
      darkTheme: hyesReadTheme(Brightness.dark),
      themeMode: mode,
      locale: language == HyesLanguage.english
          ? const Locale('en') : null,
      home: FutureBuilder<void>(
        future: startup,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 540),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 48),
                        const SizedBox(height: 16),
                        Text(language == HyesLanguage.english
                            ? 'Could not load library' : '书库加载遇到问题',
                          style: const TextStyle(fontSize: 22)),
                        const SizedBox(height: 12),
                        Text(snapshot.error.toString(), textAlign: TextAlign.center),
                        const SizedBox(height: 18),
                        Text(language == HyesLanguage.english
                            ? 'Your library data has not been changed.'
                            : '本地书库数据未被更改。'),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return AppShell(
            repository: repository, mode: mode, onModeChanged: _updateMode,
            onThemePressed: _updateModeAt,
            language: language, onLanguageChanged: _updateLanguage,
            animationsEnabled: animationsEnabled,
            onAnimationsChanged: _updateAnimationsEnabled,
          );
        },
      ),
    );
  }
}

/// Cut the circular hole out of the old frame. Only the outgoing frame is
/// drawn, so the new themed widgets are interactive without transient tinting.
class _PaperThemeReveal extends CustomPainter {
  const _PaperThemeReveal({required this.oldFrame,
    required this.origin, required this.fraction});
  final ui.Image oldFrame;
  final Offset origin;
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || fraction >= 1) return;
    final rect = Offset.zero & size;
    final farX = math.max(origin.dx, size.width - origin.dx);
    final farY = math.max(origin.dy, size.height - origin.dy);
    final radius = math.sqrt(farX * farX + farY * farY) * fraction;
    final outsideCircle = Path.combine(PathOperation.difference,
      Path()..addRect(rect), Path()..addOval(
        Rect.fromCircle(center: origin, radius: radius)));
    canvas.save();
    canvas.clipPath(outsideCircle);
    canvas.drawImageRect(oldFrame,
      Rect.fromLTWH(0, 0,
        oldFrame.width.toDouble(), oldFrame.height.toDouble()),
      rect, Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PaperThemeReveal old) =>
      old.oldFrame != oldFrame || old.origin != origin ||
      old.fraction != fraction;
}
