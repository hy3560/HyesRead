import 'package:flutter/foundation.dart';

import 'epub_location.dart';

/// The part of the reader view the controller drives.
abstract interface class EpubReaderNavigator {
  /// Shows [location].
  Future<void> jumpTo(EpubLocation location);

  /// Shows the target of [href] (a full book path, optional `#fragment`).
  /// Returns false when it is not a spine document.
  Future<bool> jumpToHref(String href);

  /// Advances a physical page or facing pair when supported.
  Future<void> turnScreen(int direction);

  /// Facing-page information, null for non-spread reader modes.
  int? get facingPairIndex;
  int? get facingPairCount;
  bool canTurnScreen(int direction);

  /// Number of spine items.
  int get chapterCount;
}

/// Drives an `EpubReaderView` and exposes its reading position.
///
/// Listeners are notified whenever [location] changes, whether by user
/// scrolling or by one of the jump methods.
class EpubReaderController extends ChangeNotifier {
  /// Creates a controller.
  EpubReaderController();

  EpubReaderNavigator? _navigator;
  EpubLocation _location = EpubLocation.start;

  /// The current reading position.
  EpubLocation get location => _location;

  /// Whether an `EpubReaderView` is using this controller.
  bool get isAttached => _navigator != null;

  /// Called by the view. Not for application code.
  void attach(EpubReaderNavigator navigator) => _navigator = navigator;

  /// Called by the view. Not for application code.
  void detach(EpubReaderNavigator navigator) {
    if (identical(_navigator, navigator)) _navigator = null;
  }

  /// Called by the view when the position changes. Not for application code.
  void updateLocation(EpubLocation location) {
    if (location == _location) return;
    _location = location;
    notifyListeners();
  }

  EpubReaderNavigator get _nav {
    final nav = _navigator;
    if (nav == null) {
      throw StateError(
          'EpubReaderController is not attached to an EpubReaderView');
    }
    return nav;
  }

  /// Shows [location].
  Future<void> jumpTo(EpubLocation location) => _nav.jumpTo(location);

  /// Shows the target of [href], a full book path with an optional
  /// `#fragment` (as found in `EpubNavItem.href`). Returns false when the
  /// document is not in the spine.
  Future<bool> jumpToHref(String href) => _nav.jumpToHref(href);

  /// Advances the next/previous physical spread instead of skipping chapters.
  Future<void> turnScreen(int direction) => _nav.turnScreen(direction);

  int? get facingPairIndex => _navigator?.facingPairIndex;
  int? get facingPairCount => _navigator?.facingPairCount;
  bool canTurnScreen(int direction) =>
      _navigator?.canTurnScreen(direction) ?? false;

  /// Shows the start of the spine item [spineIndex].
  Future<void> jumpToChapter(int spineIndex) =>
      jumpTo(EpubLocation(spineIndex: spineIndex));

  /// Shows the start of the next chapter, if any.
  Future<void> nextChapter() async {
    final next = _location.spineIndex + 1;
    if (next < _nav.chapterCount) await jumpToChapter(next);
  }

  /// Shows the start of the previous chapter, if any.
  Future<void> previousChapter() async {
    final previous = _location.spineIndex - 1;
    if (previous >= 0) await jumpToChapter(previous);
  }
}
