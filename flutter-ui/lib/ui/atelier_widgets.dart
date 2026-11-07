import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../data/book_entry.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../widgets/book_cover.dart';
import 'app_language.dart';
import 'atelier_stage.dart';

/// Colours shared by the library and reading views.
class AtelierColor {
  const AtelierColor._();
  static const forest = Color(0xFF26372F);
  static const darkForest = Color(0xFF263129);
  static const ground = Color(0xFFF1EDE4);
  static const paper = Color(0xFFFAF6EE);
  static const quieter = Color(0xFF69746B);
  static const cinnabar = Color(0xFFA9412D);
  static const gold = Color(0xFFCCBC95);
  static const night = Color(0xFF141311);
  // Both rail variants are the same pine-black pigment; only the depth
  // changes. Avoid the former day-green/night-brown identity split.
  static const nightRail = Color(0xFF1B2722);
  static const nightRaised = Color(0xFF26251F);
  static const nightInk = Color(0xFFF0E9DC);
  static const nightSecondary = Color(0xFFA89F90);
  static const nightAccent = Color(0xFFE4573D);

  static bool dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color foreground(BuildContext context) =>
      dark(context) ? nightInk : forest;
  static Color sheet(BuildContext context) =>
      dark(context) ? nightRaised : paper;
  static Color groundFor(BuildContext context) =>
      dark(context) ? night : ground;
  static Color secondary(BuildContext context) =>
      dark(context) ? nightSecondary : quieter;
  static Color accent(BuildContext context) =>
      dark(context) ? nightAccent : cinnabar;
  static Color rail(BuildContext context) =>
      dark(context) ? nightRail : darkForest;
  static Color rule(BuildContext context) =>
      foreground(context).withValues(alpha: dark(context) ? .18 : .16);
}

class AtelierBrandMark extends StatelessWidget {
  const AtelierBrandMark({
    super.key, this.size = 38, this.darkSurface = true,
  });
  final double size;
  final bool darkSurface;

  /// One restrained seal mark for both desktop and mobile. No spring,
  /// scaling, or repeated tickers: brand recognition must be stable.
  @override
  Widget build(BuildContext context) {
    final vermilion = darkSurface
        ? AtelierColor.nightAccent : AtelierColor.cinnabar;
    return Semantics(
      image: true,
      label: 'HyesRead',
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size + 4,
          child: Center(
            child: Transform.rotate(
              angle: -.0524,
              child: Container(
                width: size, height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: vermilion, width: size >= 34 ? 1.6 : 1.3),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text('阅',
                  style: TextStyle(
                    fontSize: size * .52, height: 1,
                    color: vermilion,
                    fontFamily: HyesTokens.serifFamily,
                    fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AtelierBookGarden extends StatelessWidget {
  const AtelierBookGarden({
    super.key, required this.book, this.coverWidth = 290,
    this.hero = true, this.onOpen,
  });
  final BookEntry book;
  final double coverWidth;
  final bool hero;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => AtelierStage(
    book: book, coverWidth: coverWidth, hero: hero, onOpen: onOpen);
}

/// A native file-drop affordance that matches the HTML's dashed paper well.
class AtelierDropZone extends StatelessWidget {
  const AtelierDropZone({
    super.key, required this.highlighted, required this.enabled,
    required this.language, required this.onTap,
  });
  final bool highlighted, enabled;
  final HyesLanguage language;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final night = AtelierColor.dark(context);
    final accent = AtelierColor.accent(context);
    final ink = AtelierColor.foreground(context);
    final secondary = AtelierColor.secondary(context);
    final english = language == HyesLanguage.english;
    final touchImport = Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS;
    return Material(color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          key: const ValueKey('atelier-drop-hover'),
          duration: HyesMotion.duration(
            context, const Duration(milliseconds: 270)),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: highlighted
                ? accent.withValues(alpha: night ? .12 : .09)
                : AtelierColor.sheet(context)
                    .withValues(alpha: night ? .4 : .72),
          ),
          child: CustomPaint(
            painter: _AtelierDashPainter(
              color: highlighted ? accent
                  : secondary.withValues(alpha: .32)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 112),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 22, vertical: 20),
                child: Row(children: [
                  Icon(highlighted
                      ? Icons.file_download_done_rounded
                      : Icons.file_upload_outlined,
                    size: 28,
                    color: highlighted ? accent : secondary),
                  const SizedBox(width: 18),
                  Expanded(child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(touchImport
                          ? (english ? 'Add books' : '添加书籍')
                          : (english ? 'Drop books here to import'
                              : '将书籍拖到这里，直接上架'),
                        style: TextStyle(fontSize: 17,
                          fontWeight: FontWeight.w600, color: ink)),
                      const SizedBox(height: 6),
                      Text('EPUB · TXT · MD · PDF',
                        style: TextStyle(fontSize: 13,
                          color: secondary)),
                    ],
                  )),
                  Icon(Icons.arrow_forward_rounded,
                    size: 19,
                    color: highlighted ? accent : secondary),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AtelierDashPainter extends CustomPainter {
  const _AtelierDashPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 1 || size.height <= 1) return;
    final path = Path()..addRRect(RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(1),
      const Radius.circular(15)));
    final ink = Paint()..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..strokeCap = StrokeCap.round;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance,
          math.min(metric.length, distance + 7)), ink);
        distance += 13;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AtelierDashPainter old) =>
      color != old.color;
}

/// Functional night-mode "recent" card, matching the supplied HTML's shelf.
class AtelierRecentMini extends StatelessWidget {
  const AtelierRecentMini({
    super.key, required this.book, required this.onOpen,
    required this.subtitle,
  });
  final BookEntry book;
  final VoidCallback onOpen;
  final String subtitle;

  @override
  Widget build(BuildContext context) => AtelierHoverLift(
    elevation: 4, shadow: true,
    child: Material(
      color: AtelierColor.sheet(context),
      borderRadius: BorderRadius.circular(13),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('atelier-recent-${book.id}'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(13),
        child: Semantics(
          label: '${book.title} · $subtitle',
          button: true,
          child: Padding(padding: const EdgeInsets.all(13),
            child: SizedBox(
              height: math.max(99.0, 99.0 +
                (MediaQuery.textScalerOf(context).scale(16) / 16 - 1)
                  .clamp(0.0, 4.0) * 82),
              child: Row(children: [
              AtelierCoverTilt(child: BookCover(
                book: book, width: 66, height: 99, elevation: false)),
              const SizedBox(width: 15),
              Expanded(child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(book.title.replaceAll(RegExp('[《》]'), ''),
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: HyesTokens.serifFamily, fontSize: 16,
                      fontWeight: FontWeight.w600, height: 1.35,
                      color: AtelierColor.foreground(context))),
                  const SizedBox(height: 8),
                  Text(subtitle, maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13,
                      color: AtelierColor.secondary(context))),
                ],
              )),
            ])),
          ),
        ),
      ),
    ),
  );
}

class AtelierResumePoster extends StatelessWidget {
  const AtelierResumePoster({
    super.key, required this.book, required this.onRead,
    required this.onBrowse, required this.translate,
  });
  final BookEntry book;
  final VoidCallback onRead, onBrowse;
  final String Function(String) translate;

  @override
  Widget build(BuildContext context) => _EditorialHero(
    book: book,
    onRead: onRead,
    onBrowse: onBrowse,
    translate: translate,
  );
}

/// Featured book layout used by both light and dark themes.
class _EditorialHero extends StatelessWidget {
  const _EditorialHero({
    required this.book, required this.onRead, required this.onBrowse,
    required this.translate,
  });
  final BookEntry book;
  final VoidCallback onRead, onBrowse;
  final String Function(String) translate;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final narrow = box.maxWidth < 775 ||
          MediaQuery.textScalerOf(context).scale(16) > 24;
      final compactPhone = box.maxWidth < 550 &&
          MediaQuery.textScalerOf(context).scale(16) <= 24;
      final ink = AtelierColor.foreground(context);
      final subdued = AtelierColor.secondary(context);
      final red = AtelierColor.accent(context);
      final cover = SizedBox(
        key: const ValueKey('atelier-night-cover'),
        width: compactPhone ? 145 : narrow ? 220 : 350,
        height: compactPhone ? 214 : narrow ? 285 : 472,
        child: AtelierStage(book: book,
          coverWidth: compactPhone ? 128 : narrow ? 185 : 273,
          editorial: true, hero: true, onOpen: onRead),
      );
      final heading = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: compactPhone ? 24 : 38,
              height: 1, color: red),
            SizedBox(width: compactPhone ? 9 : 14),
            Text(translate('续读'),
              style: TextStyle(color: red,
                fontSize: compactPhone ? 11 : 13,
                letterSpacing: compactPhone ? 1.6 : 2.7,
                fontWeight: FontWeight.w600)),
          ]),
          SizedBox(height: compactPhone ? 12 : 28),
          Text(book.title.replaceAll(RegExp('[《》]'), ''),
            maxLines: 3, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: HyesTokens.serifFamily,
              fontSize: compactPhone ? 25 : narrow ? 38 : 55,
              height: compactPhone ? 1.23 : 1.18,
              fontWeight: FontWeight.w600, color: ink,
              letterSpacing: compactPhone ? 0 : .6)),
          SizedBox(height: compactPhone ? 8 : 13),
          Text(book.format.toUpperCase(),
            style: TextStyle(color: subdued,
              fontSize: compactPhone ? 12 : 14, letterSpacing: 1.6)),
        ],
      );
      final progressAndActions = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(translate('阅读进度'),
            style: TextStyle(color: subdued, fontSize: 12,
              letterSpacing: 1.1)),
          SizedBox(height: compactPhone ? 3 : 5),
          Text('${(book.progress.clamp(0.0, 1.0) * 100).round()}%',
            key: const ValueKey('atelier-reading-percent'),
            maxLines: 1,
            style: TextStyle(color: ink.withValues(alpha: .96),
              fontFamily: HyesTokens.serifFamily,
              fontFeatures: const [FontFeature.tabularFigures()],
              fontSize: compactPhone ? 29 : narrow ? 30 : 37,
              height: 1.12,
              fontWeight: FontWeight.w600)),
          SizedBox(height: compactPhone ? 11 : 22),
          Container(height: 1, color: AtelierColor.rule(context)
              .withValues(alpha: .68)),
          SizedBox(height: compactPhone ? 10 : 19),
          if (book.hasReading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: book.progress.clamp(0.0, 1.0)),
                duration: HyesMotion.duration(context,
                  const Duration(milliseconds: 950)),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => LinearProgressIndicator(
                  key: const ValueKey('atelier-night-progress'),
                  value: value, minHeight: 3,
                  backgroundColor: ink.withValues(alpha: .14),
                  valueColor: AlwaysStoppedAnimation(red)),
              ),
            ),
          ],
          SizedBox(height: compactPhone ? 16 : 27),
          Wrap(spacing: compactPhone ? 10 : 15, runSpacing: 13,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AtelierMagneticButton(child: FilledButton.icon(
                key: const ValueKey('atelier-resume-open'),
                onPressed: onRead,
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                iconAlignment: IconAlignment.end,
                label: Text(translate('继续阅读')),
                style: FilledButton.styleFrom(
                  backgroundColor: red, foregroundColor: Colors.white,
                  minimumSize: Size(compactPhone ? 145 : 171,
                    compactPhone ? 48 : 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7)),
                ),
              )),
              AtelierHoverLift(elevation: 2,
                child: OutlinedButton(
                  onPressed: onBrowse,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ink,
                    minimumSize: Size(compactPhone ? 108 : 116,
                      compactPhone ? 48 : 50),
                    side: BorderSide(color: ink.withValues(alpha: .18)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
                  child: Text(translate('浏览书架')))),
            ],
          ),
        ],
      );
      final info = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading,
          const SizedBox(height: 18),
          progressAndActions,
        ],
      );
      if (compactPhone) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 6, 0, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                cover,
                const SizedBox(width: 14),
                Expanded(child: AtelierEditorialEnter(
                  horizontalTravel: 8, delay: .12, child: heading)),
              ]),
              const SizedBox(height: 9),
              progressAndActions,
            ],
          ),
        );
      }
      if (narrow) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 15),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: cover),
            const SizedBox(height: 23),
            AtelierEditorialEnter(
              horizontalTravel: 10, delay: .12, child: info),
          ]),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(height: 505,
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            cover,
            const SizedBox(width: 64),
            Expanded(child: AtelierEditorialEnter(
              delay: .14, child: info)),
          ]),
        ),
      );
    },
  );
}

class AtelierShelfFeature extends StatelessWidget {
  const AtelierShelfFeature({
    super.key, required this.book, required this.onOpen,
    required this.translate,
    this.actions,
  });
  final BookEntry book;
  final VoidCallback onOpen;
  final String Function(String) translate;
  final Widget? actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
    final narrow = box.maxWidth < 760;
    final ink = AtelierColor.foreground(context);
    final sheet = AtelierColor.sheet(context);
    final main = Padding(
      padding: EdgeInsets.all(narrow ? 25 : 38),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(translate(book.hasReading ? '正在阅读' : '未开始'),
            style: TextStyle(
              fontSize: 13, color: AtelierColor.accent(context),
              letterSpacing: 1.3, fontWeight: FontWeight.w600)),
          const SizedBox(height: 13),
          Text(book.title, maxLines: 3, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: HyesTokens.serifFamily,
                  fontSize: narrow ? 28 : 32, height: 1.3,
                  color: ink, fontWeight: FontWeight.w600)),
          const SizedBox(height: 7),
          Text(book.format.toUpperCase(), style: TextStyle(
            fontSize: 13, color: AtelierColor.secondary(context))),
          const SizedBox(height: 25),
          Text('${(book.progress.clamp(0.0, 1.0) * 100).round()}%',
            key: const ValueKey('atelier-reading-percent'),
            maxLines: 1,
            style: TextStyle(fontSize: 29,
              fontFamily: HyesTokens.serifFamily, color: ink,
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w600)),
          if (book.hasReading) ...[
            const SizedBox(height: 13),
            LinearProgressIndicator(
              value: book.progress.clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: const Color(0xFFC7CDBC),
              valueColor: AlwaysStoppedAnimation(
                AtelierColor.accent(context))),
          ],
          const SizedBox(height: 25),
          Row(children: [
            AtelierHoverLift(elevation: 2, child: TextButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.arrow_forward_rounded, size: 17),
              iconAlignment: IconAlignment.end,
              label: Text(translate('继续阅读')),
              style: TextButton.styleFrom(
                foregroundColor: AtelierColor.accent(context),
                minimumSize: const Size(124, 45)))),
            const Spacer(),
            if (actions != null) actions!,
          ]),
        ]),
    );
    return DecoratedBox(
      decoration: BoxDecoration(color: sheet,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AtelierColor.rule(context)),
        boxShadow: [BoxShadow(
          color: const Color(0xFF161C16).withValues(alpha: .045),
          blurRadius: 32, offset: const Offset(0, 11))]),
      child: narrow ? Column(children: [
        Material(color: Colors.transparent, child: InkWell(
          key: const ValueKey('atelier-feature-open'),
          onTap: onOpen,
          child: Semantics(button: true, label: book.title,
            child: SizedBox(width: double.infinity, height: 320,
              child: AtelierStage(book: book, coverWidth: 205,
                editorial: true, onOpen: onOpen))),
        )),
        main,
      ]) : SizedBox(height: 340, child: Row(children: [
        Material(color: Colors.transparent, child: InkWell(
          key: const ValueKey('atelier-feature-open'),
          onTap: onOpen,
          child: Semantics(button: true, label: book.title,
            child: SizedBox(width: 315,
              child: AtelierStage(
                book: book, coverWidth: 223,
                editorial: true, onOpen: onOpen))),
        )),
        Expanded(child: main),
      ])),
    );
  });
}
