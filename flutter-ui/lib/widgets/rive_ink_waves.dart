import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:rive/rive.dart' as rive;

import '../design/motion.dart';
import '../design/tokens.dart';

/// One-shot ink ripple driven by a real Rive state machine, not a fake
/// Flutter stand-in. This tiny 947-byte circle/state-machine sample is
/// embedded from rive 0.14.11/example/assets/runtime_nested_inputs.riv,
/// released with the MIT-licensed Rive Flutter runtime, so the reading app
/// needs no network, editor account or potentially unlicensed community art.
/// It is tinted vermilion to obey the one-accent design constraint.
/// If native setup is unavailable, the surrounding stamp still works.
const _riveExampleBytes =
    'UklWRQcAkYQBxAHuA+MBxQHgAeQBxgHsAeEB7QEAAAAAAAAAAAAAAAAAFwABBAxNYWluQXJ0Ym9hcmQHAABIQwgAAEhD7gMG7AEAAFwEC0NpcmNsZU91dGVyBQANAADIQQ4AAMhBxQECAF8FAcYBAAB7BQLtAQIAegUC7QEBAHwFAu0BAACkAwUAABIFCCUxMTH/ABQFAAAfNwpUaW1lbGluZSAyAB83ClRpbWVsaW5lIDEANTcQTWFpblN0YXRlTWFjaGluZQA7igEITWFpbkJvb2wAOYoBB0xheWVyIDEAQAA+AEGXAQMAR5sBAJwBAQBBlwEEAEebAQAAPwA9lQEBAD2VAQAAcgB14wEA5AECAAEEC0NpcmNsZUlubmVyxAEABwAAyEIIAADIQu4DBAkAANFDCgAAEEHsAQAAAwUADQAASEIOAABIQgAEBQEUAADIQhUAAMhCABIFBQCkAwUAABQFAQAfNwpUaW1lbGluZSAyABkzAwAaNSUAJUQBWGwb/f8AHzcKVGltZWxpbmUgMQAZMwMAGjUlACVEAVh0dHT/ADU3D1N0YXRlIE1hY2hpbmUgMQA4igERQ2lyY2xlSW5uZXJOdW1iZXIAO4oBEkNpcmNsZUlubmVyVHJpZ2dlcgA7igEQQ2lyY2xlSW5uZXJTdGF0ZQA5igEHTGF5ZXIgMQA9lQEAAD8APgBBlwEDAEebAQKcAQEAQZcBAABHmwECAD2VAQEAQAABBAtDaXJjbGVPdXRlcsQBAAcAABZDCAAAFkPuAwkJAABtQwoAAIBA7AEAAFwEC0NpcmNsZUlubmVyBQANAADIQQ4AAMhBxQEBAF8FAcYBAAB7BQLtAQIAewUC7QEBAHwFAu0BAAADBQANAACWQg4AAJZCAAQFBhQAABZDFQAAFAUGAB83ClRpbWVsaW5lIDIAGTMIABo1JQAlRAFYLv0f/wAfNwpUaW1lbGluZSAxABkzCAAaNSUAJUQBWHR0dP8ANTcSQ2lyY2xlU3RhdGVNYWNoaW5lADiKARFDaXJjbGVPdXRlck51bWJlcgA6igESQ2lyY2xlT3V0ZXJUcmlnZ2VyADuKARBDaXJjbGVPdXRlclN0YXRlADmKAQdMYXllciAxAD4AQZcBBABHmwECnAEBAEGXAQEAR5sBAgA9lQEAAD8AQAA9lQEBAHKKAQdFbGxpcHNl4AEG4QEBAHXjAQLkAQAAcooBB0VsbGlwc2XgAQYAdeMBAgA=';

/// The custom Rive view is optional and isolated from the reader itself.
/// The explicit event counter can retrigger a fresh impression.
class RiveInkWaves extends StatefulWidget {
  const RiveInkWaves({super.key, this.impression = 0, this.size = 116});
  final int impression;
  final double size;

  @override
  State<RiveInkWaves> createState() => _RiveInkWavesState();
}

class _RiveInkWavesState extends State<RiveInkWaves> {
  rive.File? _file;
  rive.RiveWidgetController? _controller;
  int _lastPulsedImpression = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller == null && Platform.isAndroid &&
        !HyesMotion.reduced(context)) {
      _prepare();
    }
  }

  Future<void> _prepare() async {
    if (_loading) return;
    _loading = true;
    try {
      final bytes = Uint8List.fromList(base64Decode(_riveExampleBytes));
      final file = await rive.File.decode(bytes,
          riveFactory: rive.Factory.flutter);
      if (file == null) return;
      if (!mounted || HyesMotion.reduced(context)) {
        file.dispose();
        return;
      }
      final controller = rive.RiveWidgetController(file);
      setState(() {
        _file = file;
        _controller = controller;
      });
      _pulseIfNeeded();
    } catch (_) {
      // A missing Rive native library must not break book import or reading.
    } finally {
      _loading = false;
    }
  }

  bool _loading = false;

  void _pulseIfNeeded() {
    // Decoding can finish before or after the seal lands. Never fire the
    // ripple on decoder completion alone, or twice for one impression.
    if (_controller == null || widget.impression <= 0 ||
        widget.impression == _lastPulsedImpression) {
      return;
    }
    _lastPulsedImpression = widget.impression;
    // These inputs are part of the above sample. Trigger names are optional,
    // as the runtime may choose a different default state machine.
    _controller?.stateMachine.trigger('CircleOuterTrigger')?.fire();
    _controller?.stateMachine.trigger('CircleInnerTrigger')?.fire();
  }

  @override
  void didUpdateWidget(covariant RiveInkWaves oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.impression != oldWidget.impression) _pulseIfNeeded();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _file?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = HyesTokens.of(context).vermilion;
    if (HyesMotion.reduced(context) || _controller == null) {
      return SizedBox.square(dimension: widget.size);
    }
    return IgnorePointer(child: ColorFiltered(
      colorFilter: ColorFilter.mode(color.withValues(alpha: .55),
        BlendMode.srcIn),
      child: SizedBox.square(dimension: widget.size,
        child: rive.RiveWidget(controller: _controller!,
          fit: rive.Fit.contain)),
    ));
  }
}
