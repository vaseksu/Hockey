// ─── HockeyView.mc ────────────────────────────────────────────────────────────
// Main display for the Fenix 8 AMOLED 51mm (454 × 454 px, round, black bg).
//
// Layout (all coordinates are %-based so it scales to 47 mm and Solar too):
//
//  ┌──────────────────────────────┐
//  │         HOCKEY SHIFTS        │  ← title (tiny, grey)
//  │                              │
//  │          ON ICE              │  ← state (large, coloured)
//  │           02:34              │  ← current shift/bench timer
//  │  ─────────────────────────── │
//  │         Shifts: 8            │
//  │         TOI:  14:30          │
//  │         Avg:   0:43          │
//  │         Last:  0:38          │
//  │                              │
//  │      HR:165   Ac:620  [SIM]  │  ← debug row (dim)
//  └──────────────────────────────┘
//
//  State colours (AMOLED-optimised, dark background):
//    ON_BENCH          → #FF6600 (orange)
//    GOING_ON_ICE      → #FFDD00 (yellow – transitioning)
//    ON_ICE            → #00AAFF (ice blue)
//    GOING_TO_BENCH    → #FFDD00 (yellow – transitioning)
// ──────────────────────────────────────────────────────────────────────────────

import Toybox.Activity;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Lang;

class HockeyView extends WatchUi.View {
    private var _data     as ShiftData;
    private var _detector as ShiftDetector;

    // Colour palette
    private const C_BG          as Number = Graphics.COLOR_BLACK;
    private const C_ICE         as Number = 0x00AAFF; // ice blue
    private const C_BENCH       as Number = 0xFF6600; // orange
    private const C_TRANSITION  as Number = 0xFFDD00; // yellow
    private const C_TEXT        as Number = Graphics.COLOR_WHITE;
    private const C_DIM         as Number = 0x666666;
    private const C_DIVIDER     as Number = 0x333333;

    function initialize(data as ShiftData, detector as ShiftDetector) {
        View.initialize();
        _data     = data;
        _detector = detector;
    }

    function onLayout(dc as Graphics.Dc) as Void {
        // All drawing is done in onUpdate; no XML layout needed.
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w  = dc.getWidth();    // 454 on Fenix 8 51mm
        var h  = dc.getHeight();   // 454
        var cx = w / 2;

        // ── Black background ──────────────────────────────────────────────────
        dc.setColor(C_BG, C_BG);
        dc.fillRectangle(0, 0, w, h);

        var J = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        // ── State label ───────────────────────────────────────────────────────
        var state      = _detector.getState();
        var stateColor = _stateColor(state);
        var stateLabel = _stateLabel(state);
        dc.setColor(stateColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 9 / 100, Graphics.FONT_MEDIUM, stateLabel, J);

        // ── AHR (left), Timer (center), CAL (right) ───────────────────────────
        var actInfo = Activity.getActivityInfo();
        var avgHR;
        var cals;
        if (_data.isSimulation) {
            avgHR = (_data.simAvgHR > 0) ? _data.simAvgHR.toString() : "--";
            cals  = (_data.simCals  > 0) ? _data.simCals.toString()  : "--";
        } else {
            avgHR = (actInfo != null && actInfo.averageHeartRate != null)
                        ? (actInfo.averageHeartRate as Number).toString()
                        : "--";
            cals  = (actInfo != null && actInfo.calories != null)
                        ? (actInfo.calories as Number).toString()
                        : "--";
        }

        var sideX1 = w * 18 / 100;
        var sideX2 = w * 82 / 100;

        // AHR and CAL: label + value stacked tightly, flanking the timer
        dc.setColor(C_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(sideX1, h * 20 / 100, Graphics.FONT_XTINY, "AHR", J);
        dc.drawText(sideX2, h * 20 / 100, Graphics.FONT_XTINY, "CAL", J);
        dc.setColor(C_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(sideX1, h * 28 / 100, Graphics.FONT_TINY, avgHR, J);
        dc.drawText(sideX2, h * 28 / 100, Graphics.FONT_TINY, cals,  J);

        var timerStr = _data.msToStr(_detector.getCurrentDurationMs());
        dc.drawText(cx, h * 23 / 100, Graphics.FONT_NUMBER_MILD, timerStr, J);

        // ── Heart rate + G/A flanking ─────────────────────────────────────────
        var hrVal = _data.currentHR;
        var hrStr = (hrVal > 0) ? hrVal.toString() : "--";
        dc.setColor(C_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(sideX1, h * 38 / 100, Graphics.FONT_XTINY, "G", J);
        dc.drawText(sideX2, h * 38 / 100, Graphics.FONT_XTINY, "A", J);
        dc.setColor(_hrColor(hrVal), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 43 / 100, Graphics.FONT_NUMBER_MILD, hrStr, J);
        dc.setColor(C_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(sideX1, h * 47 / 100, Graphics.FONT_MEDIUM, _data.goals.toString(),   J);
        dc.drawText(sideX2, h * 47 / 100, Graphics.FONT_MEDIUM, _data.assists.toString(), J);
        dc.setColor(C_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 53 / 100, Graphics.FONT_XTINY, "bpm", J);

        // ── Divider ───────────────────────────────────────────────────────────
        dc.setColor(C_DIVIDER, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(w * 15 / 100, h * 58 / 100, w * 85 / 100, h * 58 / 100);

        // ── Statistics grid ───────────────────────────────────────────────────
        var col1 = w * 38 / 100;
        var col2 = w * 62 / 100;

        dc.setColor(C_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(col1, h * 63 / 100, Graphics.FONT_TINY, "SHIFTS", J);
        dc.drawText(col2, h * 63 / 100, Graphics.FONT_TINY, "TOI",    J);
        dc.setColor(C_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(col1, h * 72 / 100, Graphics.FONT_SMALL, _data.getShiftCount().toString(), J);
        dc.drawText(col2, h * 72 / 100, Graphics.FONT_SMALL, _data.msToStr(_data.totalToiMs),  J);

        dc.setColor(C_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(col1, h * 82 / 100, Graphics.FONT_TINY, "AVG",  J);
        dc.drawText(col2, h * 82 / 100, Graphics.FONT_TINY, "LAST", J);
        dc.setColor(C_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(col1, h * 91 / 100, Graphics.FONT_SMALL, _data.msToStr(_data.getAvgShiftMs()), J);
        if (_data.getShiftCount() > 0) {
            dc.drawText(col2, h * 91 / 100, Graphics.FONT_SMALL, _data.msToStr(_data.getLastShiftMs()), J);
        }

        // ── Simulation badge – top-right corner ──────────────────────────────
        if (_data.isSimulation) {
            dc.setColor(C_TRANSITION, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w * 88 / 100, h * 5 / 100, Graphics.FONT_XTINY, "SIM", J);
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    // HR colour: mirrors the detection thresholds for instant visual feedback
    //   --   → dim (no data)
    //   <100 → white  (resting)
    //  100–119 → orange (bench-level exertion)
    //  120–144 → yellow (threshold zone)
    //  ≥145  → ice blue (on-ice intensity)
    private function _hrColor(hr as Number) as Number {
        if (hr <= 0)   { return C_DIM;        }
        if (hr < 100)  { return C_TEXT;        }
        if (hr < 120)  { return C_BENCH;       }
        if (hr < 145)  { return C_TRANSITION;  }
        return C_ICE;
    }

    private function _stateColor(state as Number) as Number {
        if (state == STATE_ON_ICE)        { return C_ICE;        }
        if (state == STATE_GOING_ON_ICE)  { return C_TRANSITION;  }
        if (state == STATE_GOING_TO_BENCH){ return C_TRANSITION;  }
        return C_BENCH; // STATE_BENCH
    }

    private function _stateLabel(state as Number) as String {
        if (state == STATE_ON_ICE)         { return "ON ICE";    }
        if (state == STATE_GOING_ON_ICE)   { return ">>> ICE";   }
        if (state == STATE_GOING_TO_BENCH) { return ">>> BENCH"; }
        return "BENCH";
    }
}
