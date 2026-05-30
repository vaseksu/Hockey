// ─── SimulationHelper.mc ──────────────────────────────────────────────────────
// Injects synthetic HR + accelerometer data so you can fully test the detection
// algorithm, state machine, and UI on the Connect IQ Simulator without skating
// or raising your real heart rate.
//
// How to activate:
//   Long-press the UP button → menu → "Run Simulation"
//
// The simulation replays a realistic 7-minute rec-hockey excerpt:
//   bench (15 s) → shift (40 s) → bench (90 s) → shift (38 s) →
//   bench (90 s) → shift (42 s) → bench (rest)
//
// Each step ramps HR gradually (not a step function) to mimic real physiology:
//   • Bench → ice: HR climbs over ~30 s to peak
//   • Ice  → bench: HR stays elevated for ~30 s then descends
// Accel changes instantly since arm movement is the physical trigger.
//
// Drives the same ShiftDetector.injectData() path as real
// sensor data, so every code path is exercised identically.
//
// The simulation deliberately exercises the HRM-Pro fast path:
// when stepping onto ice, HR rises at ~5 bpm/s (well above HR_DELTA_FAST_BPM=3),
// so the ice confirmation fires in ~3 s rather than 8 s. You can see this
// difference vs the bench→ice transitions where HR ramps are slower.
// ──────────────────────────────────────────────────────────────────────────────

import Toybox.Lang;
import Toybox.System;
import Toybox.Math;

// ── Sequence step description ─────────────────────────────────────────────────
// [targetHR, targetAccel, durationMs]
// HR is linearly ramped from the previous step's HR to targetHR over the step.
// Accel changes immediately to targetAccel.

class SimulationHelper {
    private var _detector    as ShiftDetector;
    private var _data        as ShiftData;
    private var _active      as Boolean;
    private var _stepIdx     as Number;
    private var _stepStartMs as Number;
    private var _prevHR      as Number;
    private var _hrSum       as Number;
    private var _hrCount     as Number;
    private var _ticks       as Number;

    // Sequence: [targetHR, targetAccel, durationMs]
    // Bench phases: HR ~80–120, accel ~30–60 mg
    // Ice phases  : HR ~150–180, accel ~550–700 mg
    private var _seq as Array<Array<Number>>;

    function initialize(detector as ShiftDetector, data as ShiftData) {
        _detector = detector;
        _data     = data;
        _active   = false;
        _stepIdx  = 0;
        _stepStartMs = 0;
        _prevHR   = 80;
        _hrSum    = 0;
        _hrCount  = 0;
        _ticks    = 0;

        // Each row: [targetHR, targetAccel, durationMs]
        _seq = [
            [85,  45,  15000],  // bench  15 s  – resting, low movement
            [172, 630, 40000],  // shift  40 s  – skating hard
            [125, 40,  30000],  // bench  30 s  – HR cooling down
            [95,  35,  60000],  // bench  60 s  – resting
            [168, 590, 38000],  // shift  38 s
            [130, 42,  30000],  // bench  30 s  – cooling down
            [98,  30,  60000],  // bench  60 s  – resting
            [175, 650, 42000],  // shift  42 s
            [110, 35,  30000],  // bench  30 s  – cooling down
            [88,  28,  30000]   // bench  30 s  – simulation ends
        ] as Array<Array<Number>>;
    }

    function start() as Void {
        _active      = true;
        _stepIdx     = 0;
        _stepStartMs = System.getTimer();
        _prevHR      = 80;
        _hrSum       = 0;
        _hrCount     = 0;
        _ticks       = 0;
        _data.isSimulation = true;
        _data.goals        = 1;
        _data.assists      = 2;
        _data.simAvgHR     = 0;
        _data.simCals      = 0;
    }

    function isActive() as Boolean { return _active; }

    // ── Called every second from the main app timer ───────────────────────────
    // Drives the simulation forward one tick at a time.

    function onTick() as Void {
        if (!_active) { return; }

        var now = System.getTimer();

        // Advance steps if the current one has elapsed
        while (_stepIdx < _seq.size() &&
               now - _stepStartMs >= (_seq[_stepIdx] as Array<Number>)[2]) {
            _prevHR      = (_seq[_stepIdx] as Array<Number>)[0];
            _stepStartMs = _stepStartMs + (_seq[_stepIdx] as Array<Number>)[2];
            _stepIdx++;
        }

        if (_stepIdx >= _seq.size()) {
            // Simulation finished
            _active            = false;
            _data.isSimulation = false;
            return;
        }

        var step        = _seq[_stepIdx] as Array<Number>;
        var targetHR    = step[0];
        var targetAccel = step[1];
        var durationMs  = step[2];
        var elapsed     = now - _stepStartMs;

        // Linearly ramp HR from _prevHR to targetHR over the full step duration.
        // This makes HR changes look realistic rather than instantaneous.
        var ratio = elapsed.toFloat() / durationMs.toFloat();
        if (ratio > 1.0f) { ratio = 1.0f; }
        var hr = (_prevHR.toFloat() + ratio * (targetHR - _prevHR).toFloat()).toNumber();

        // Add ±5 bpm and ±50 mg noise so charts look organic
        var seed     = System.getTimer();
        var hrNoise  = (seed % 11) - 5;
        var acNoise  = ((seed / 7) % 101) - 50;
        var accel    = targetAccel + acNoise;
        hr           = hr + hrNoise;

        if (hr    < 50)  { hr    = 50;  }
        if (hr    > 210) { hr    = 210; }
        if (accel < 0)   { accel = 0;   }

        _detector.injectData(hr, accel);

        // Update simulated AHR and calories
        _hrSum   += hr;
        _hrCount++;
        _ticks++;
        _data.simAvgHR = _hrSum / _hrCount;
        _data.simCals  = _ticks * 15 / 60;  // ~15 cal/min
    }
}
