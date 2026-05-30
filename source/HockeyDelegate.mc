// ─── HockeyDelegate.mc ────────────────────────────────────────────────────────
// Handles physical button input on the Fenix 8.
//
// Button mapping (Fenix 8 activity app):
//   SELECT (top-right, short press) → add goal
//   BACK   (bottom-right, short press) → add assist  (long press exits)
//   MENU   (up button, long press)  → opens settings menu (toggle, sim, reset)
// ──────────────────────────────────────────────────────────────────────────────

import Toybox.WatchUi;
import Toybox.Lang;

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

    // Short-press SELECT (top-right) → add a goal
    function onSelect() as Boolean {
        _data.goals++;
        WatchUi.requestUpdate();
        return true;
    }

    // MENU long-press → settings / simulation menu
    function onMenu() as Boolean {
        var menu = new WatchUi.Menu2({:title => "Hockey Shifts"});
        menu.addItem(new WatchUi.MenuItem("Toggle shift",   null, :toggle,   {}));
        menu.addItem(new WatchUi.MenuItem("Run simulation",  null, :simulate, {}));
        menu.addItem(new WatchUi.MenuItem("Reset stats",     null, :reset,    {}));
        menu.addItem(new WatchUi.MenuItem("Clear G/A",       null, :clearGA,  {}));
        WatchUi.pushView(menu,
                         new HockeyMenuDelegate(_detector, _data, _sim),
                         WatchUi.SLIDE_UP);
        return true;
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
        }

        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
