// ─── HockeyDelegate.mc ────────────────────────────────────────────────────────
// Handles physical button input on the Fenix 8.
//
// Button mapping (Fenix 8 activity app):
//   DOWN   (bottom-left, short press) → add goal
//   BACK   (bottom-right, short press) → add assist
//   SELECT (top-right, short press)   → opens hockey menu
//   MENU   (up button, long press)    → opens hockey menu
// ──────────────────────────────────────────────────────────────────────────────

import Toybox.WatchUi;
import Toybox.Lang;
import Toybox.System;

class HockeyDelegate extends WatchUi.BehaviorDelegate {
    private var _detector as ShiftDetector;
    private var _data     as ShiftData;
    private var _sim      as SimulationHelper;

    function initialize(detector as ShiftDetector,
                        data     as ShiftData,
                        sim      as SimulationHelper) {
        BehaviorDelegate.initialize();
        _detector = detector;
        _data     = data;
        _sim      = sim;
    }

    // Short-press DOWN (bottom-left) → add a goal
    function onNextPage() as Boolean {
        _data.goals++;
        WatchUi.requestUpdate();
        return true;
    }

    // Short-press SELECT (top-right) → open hockey menu
    function onSelect() as Boolean {
        _openMenu();
        return true;
    }

    // MENU long-press → open hockey menu
    function onMenu() as Boolean {
        _openMenu();
        return true;
    }

    private function _openMenu() as Void {
        var menu = new WatchUi.Menu2({:title => "Hockey Shifts"});
        menu.addItem(new WatchUi.MenuItem("Toggle shift",  null, :toggle,   {}));
        menu.addItem(new WatchUi.MenuItem("Run simulation", null, :simulate, {}));
        menu.addItem(new WatchUi.MenuItem("Reset stats",    null, :reset,    {}));
        menu.addItem(new WatchUi.MenuItem("Clear G/A",      null, :clearGA,  {}));
        menu.addItem(new WatchUi.MenuItem("Stop & Save",    null, :stopSave, {}));
        menu.addItem(new WatchUi.MenuItem("Discard",        null, :discard,  {}));
        WatchUi.pushView(menu,
                         new HockeyMenuDelegate(_detector, _data, _sim),
                         WatchUi.SLIDE_UP);
    }

    // Short-press BACK (bottom-right) → add an assist.
    // Returning true consumes the press so the app stays open.
    // Long-press BACK is handled by the OS (save/exit) regardless.
    function onBack() as Boolean {
        _data.assists++;
        WatchUi.requestUpdate();
        return true;
    }
}

// ── Menu delegate ─────────────────────────────────────────────────────────────

class HockeyMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _detector as ShiftDetector;
    private var _data     as ShiftData;
    private var _sim      as SimulationHelper;

    function initialize(detector as ShiftDetector,
                        data     as ShiftData,
                        sim      as SimulationHelper) {
        Menu2InputDelegate.initialize();
        _detector = detector;
        _data     = data;
        _sim      = sim;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();

        if (id == :toggle) {
            _detector.manualToggle();

        } else if (id == :simulate) {
            _sim.start();

        } else if (id == :reset) {
            _data.reset();

        } else if (id == :clearGA) {
            _data.goals   = 0;
            _data.assists = 0;

        } else if (id == :stopSave) {
            var menu = new WatchUi.Menu2({:title => "How did you play?"});
            menu.addItem(new WatchUi.MenuItem("★★★★★  Great",   null, :feel5, {}));
            menu.addItem(new WatchUi.MenuItem("★★★★   Good",    null, :feel4, {}));
            menu.addItem(new WatchUi.MenuItem("★★★    Average", null, :feel3, {}));
            menu.addItem(new WatchUi.MenuItem("★★     Poor",    null, :feel2, {}));
            menu.addItem(new WatchUi.MenuItem("★      Bad",     null, :feel1, {}));
            WatchUi.pushView(menu,
                new EvalFeelDelegate(_data),
                WatchUi.SLIDE_UP);
            return; // do NOT pop — eval delegate takes over

        } else if (id == :discard) {
            discardAndExit();
            return;
        }

        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

// ── Evaluation: How did you play? ──────────────────────────────────────────────

class EvalFeelDelegate extends WatchUi.Menu2InputDelegate {
    private var _data as ShiftData;
    function initialize(data as ShiftData) {
        Menu2InputDelegate.initialize();
        _data = data;
    }
    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if      (id == :feel5) { _data.feelRating = 5; }
        else if (id == :feel4) { _data.feelRating = 4; }
        else if (id == :feel3) { _data.feelRating = 3; }
        else if (id == :feel2) { _data.feelRating = 2; }
        else                   { _data.feelRating = 1; }
        // Now ask effort level
        var menu = new WatchUi.Menu2({:title => "Effort level?"});
        menu.addItem(new WatchUi.MenuItem("Max effort",   null, :effort5, {}));
        menu.addItem(new WatchUi.MenuItem("Very hard",    null, :effort4, {}));
        menu.addItem(new WatchUi.MenuItem("Hard",         null, :effort3, {}));
        menu.addItem(new WatchUi.MenuItem("Moderate",     null, :effort2, {}));
        menu.addItem(new WatchUi.MenuItem("Easy",         null, :effort1, {}));
        WatchUi.pushView(menu,
            new EvalEffortDelegate(_data),
            WatchUi.SLIDE_UP);
    }
    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

// ── Evaluation: Effort level ─────────────────────────────────────────────────

class EvalEffortDelegate extends WatchUi.Menu2InputDelegate {
    private var _data as ShiftData;
    function initialize(data as ShiftData) {
        Menu2InputDelegate.initialize();
        _data = data;
    }
    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if      (id == :effort5) { _data.effortRating = 5; }
        else if (id == :effort4) { _data.effortRating = 4; }
        else if (id == :effort3) { _data.effortRating = 3; }
        else if (id == :effort2) { _data.effortRating = 2; }
        else                     { _data.effortRating = 1; }
        // Done — save and exit
        saveAndExit();
    }
    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
