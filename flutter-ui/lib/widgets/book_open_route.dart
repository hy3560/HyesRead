import 'package:flutter/material.dart';

import '../data/book_entry.dart';
import '../data/library_repository.dart';
import '../design/motion.dart';
import '../ui/reader_page.dart';

/// Cover-to-reader transition with a short spine unfold and highlight.
/// Reduced-motion settings bypass the decorative transform.
class BookOpenRoute extends PageRouteBuilder<void> {
  BookOpenRoute({
    required BookEntry book,
    required LibraryRepository repository,
    bool reduceMotion = false,
  })
      : super(
          transitionDuration: reduceMotion
              ? Duration.zero : const Duration(milliseconds: 560),
          reverseTransitionDuration: reduceMotion
              ? Duration.zero : const Duration(milliseconds: 330),
          opaque: true,
          pageBuilder: (context, animation, secondaryAnimation) =>
              ReaderPage(repository: repository, bookId: book.id),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final reduced = HyesMotion.reduced(context);
            if (reduced) return child;
            return AnimatedBuilder(
              animation: animation,
              child: child,
              builder: (context, page) {
                final phase = ((animation.value - .12) / .88)
                    .clamp(0.0, 1.0).toDouble();
                final progress = Curves.easeOutCubic.transform(phase);
                final travel = 1 - progress;
                final sheen = (1 - (animation.value * 2 - 1).abs())
                    .clamp(0.0, 1.0).toDouble();
                return Stack(fit: StackFit.expand, children: [
                  Opacity(
                    opacity: progress,
                    child: Transform.translate(
                      offset: Offset(20 * travel, 7 * travel),
                      child: Transform(
                        alignment: Alignment.centerLeft,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, .0008)
                          ..rotateY(-.085 * travel),
                        child: page,
                      ),
                    ),
                  ),
                  if (sheen > .001)
                    Positioned.fill(child: IgnorePointer(
                      child: Opacity(
                        opacity: sheen * .25,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment(-1.0 + animation.value, -.2),
                              end: Alignment(-.35 + animation.value, .2),
                              colors: const [
                                Colors.transparent,
                                Color(0xFFFFF0D4),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    )),
                ]);
              },
            );
          },
        );
}
