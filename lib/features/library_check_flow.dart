import 'package:flutter/foundation.dart';

import '../browser/browser_presentation.dart';
import '../library/library_check.dart';

/// Who is driving a Library-wide check, and what that entitles it to do to
/// what the user is looking at.
///
/// The check itself — `UpdateChecker`, the queue, and
/// `computeLibraryCheckReport` — knows nothing about tabs, routes or sheets,
/// and must not. What it cannot answer on its own is "the Browser came
/// forward for this run; who puts it back, and where does the user end up?".
/// That answer belongs to whoever *started* the run, which is what this
/// enum names.
enum LibraryCheckPresentation {
  /// Started from the Library card. It knowingly moved the user into the
  /// Browser, so it owes them the way back: hand the Browser's own surface
  /// back, return to where the run started, and show the result there.
  libraryForeground,

  /// A run with no claim on what the user is looking at. It checks, it
  /// reports, and it navigates nothing. Everything foreground-specific below
  /// is inert for such a run — which is the seam a future concurrent mode
  /// would use, without the checking engine having to change.
  unattached,
}

/// One Library-wide run, plus everything the *presentation* of that run owns.
///
/// Session state, deliberately, and separate from the run's results: the
/// results are rows in the database and outlive anything here, while "this
/// run brought the Browser forward and still owes the user a way back" is
/// true only for as long as the app is running and the user has not taken
/// over. Persisting it would mean a relaunch could yank someone out of the
/// Browser for a run that ended yesterday.
///
/// It holds no `BuildContext`, no route and no widget. It records what the
/// foreground flow took over and answers whether it still owns it; the UI
/// layer reads that and does the navigating.
class LibraryCheckFlow extends ChangeNotifier {
  LibraryCheckPlan? _plan;
  LibraryCheckPlan? get plan => _plan;

  LibraryCheckPresentation _presentation = LibraryCheckPresentation.unattached;
  LibraryCheckPresentation get presentation => _presentation;

  /// The shell tab the run was started from, and the one it returns to. For
  /// the only entry point that exists today that is the Library.
  int _returnTab = 0;
  int get returnTab => _returnTab;

  /// What the Browser was showing locally before the run — Home, the address
  /// editor, or the page itself. The run reveals the website surface to work
  /// on a page; this is what makes putting it back possible.
  BrowserSurface? _surfaceBefore;
  BrowserSurface? get surfaceBefore => _surfaceBefore;

  /// True when this run is what will bring the Browser forward. False when
  /// the user was already there, and false when the run scheduled no
  /// Browser-dependent work at all — in which case there is nothing to undo.
  bool _broughtBrowserForward = false;
  bool get broughtBrowserForward => _broughtBrowserForward;

  /// The user replaced this run's presentation with something of their own.
  /// From that point the run reports, and moves nobody.
  bool _released = false;
  bool get released => _released;

  /// Claimed once, by whoever presents the completion. Not persisted: an
  /// unpresented completion from a previous launch is not a debt this app
  /// should pay by opening a sheet at startup.
  bool _completionClaimed = false;
  bool get completionClaimed => _completionClaimed;

  /// Is this run still entitled to move the user?
  bool get ownsForeground =>
      _plan != null &&
      _presentation == LibraryCheckPresentation.libraryForeground &&
      !_released;

  /// Start a run that owns the foreground: it will take the user to the
  /// Browser and is responsible for bringing them back.
  void beginForeground({
    required LibraryCheckPlan plan,
    required int returnTab,
    required BrowserSurface surfaceBefore,
    required bool willUseBrowser,
  }) {
    _plan = plan;
    _presentation = LibraryCheckPresentation.libraryForeground;
    _returnTab = returnTab;
    _surfaceBefore = surfaceBefore;
    _broughtBrowserForward = willUseBrowser && returnTab != 1;
    _released = false;
    _completionClaimed = false;
    notifyListeners();
  }

  /// Start a run that owns nothing on screen. It checks and reports; no tab
  /// moves, no surface is restored, no sheet opens.
  void beginUnattached(LibraryCheckPlan plan) {
    _plan = plan;
    _presentation = LibraryCheckPresentation.unattached;
    _returnTab = 0;
    _surfaceBefore = null;
    _broughtBrowserForward = false;
    _released = false;
    _completionClaimed = false;
    notifyListeners();
  }

  /// The rows exist now. Keeps the presentation this run was started with.
  void attachPlan(LibraryCheckPlan plan) {
    _plan = plan;
    notifyListeners();
  }

  /// The user asked to stop. The plan records it so the report can tell
  /// "stopped" from "finished with problems".
  void requestStop() {
    final plan = _plan;
    if (plan == null) return;
    _plan = plan.asStopping();
    notifyListeners();
  }

  /// The user has taken the presentation for something else. Everything the
  /// run would have done to the screen is dropped; its results are not.
  void releaseForeground() {
    if (_released) return;
    _released = true;
    notifyListeners();
  }

  /// Take the right to present this run's completion, exactly once.
  ///
  /// Deliberately a field on the session rather than a widget's state: the
  /// Library screen can be rebuilt, recreated or revisited, and none of that
  /// may produce a second sheet.
  bool claimCompletion() {
    if (_completionClaimed) return false;
    _completionClaimed = true;
    return true;
  }

  /// Put back the Browser's own local surface, when this run is what
  /// replaced it.
  ///
  /// This is the whole of "close what the run opened". There are no browser
  /// tabs in this app and the run creates no WebView of its own: it borrows
  /// the one shared surface, and what it visibly changes is the *local*
  /// surface stacked over it. Nothing is closed, cleared or reloaded here —
  /// no page is navigated, no history, cookie or saved site is touched, and
  /// the document the WebView ended on stays exactly where it is, because
  /// putting it back would mean fetching somebody else's page again.
  void restoreBrowserSurface(BrowserPresentation presentation) {
    if (!ownsForeground) return;
    // Only the case the run actually caused. It reveals the website surface
    // to work on a page; if the user was on Home, that is what it covered.
    // An address editor is not restored — its draft is gone, and reopening a
    // keyboard over a screen the user has left is not a restoration.
    if (_surfaceBefore == BrowserSurface.home &&
        presentation.surface == BrowserSurface.website) {
      presentation.openHome();
    }
  }

  /// Forget the run. The card goes back to offering a check; the results
  /// stay where they have always been — on the collections themselves.
  void clear() {
    if (_plan == null) return;
    _plan = null;
    _presentation = LibraryCheckPresentation.unattached;
    _surfaceBefore = null;
    _broughtBrowserForward = false;
    _released = false;
    _completionClaimed = false;
    notifyListeners();
  }
}
