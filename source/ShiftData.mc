// ─── ShiftData.mc ─────────────────────────────────────────────────────────────
// Data model, shared constants, and a fixed-capacity ring buffer helper.
// ──────────────────────────────────────────────────────────────────────────────

import Toybox.Lang;
import Toybox.System;

// ── Detection thresholds (tune after real on-ice testing) ─────────────────────
//
// Real-world reference (your activity 23009826047):
//   HR bench: ~82 bpm  |  HR on-ice peak: ~191 bpm  |  avg: 157 bpm
//   Device: Fenix 8 AMOLED 51mm + HRM-Pro Plus chest strap
//
// Accel values are wrist deviation from 1 g (1000 mg) in milli-g.
//   At rest the wrist barely moves  → low deviation (~20–80 mg)
//   Skating stride swings the arm   → high deviation (~400–1000 mg)

const HR_ICE_THRESHOLD      as Number = 145; // bpm – HR above this → probably on ice
const HR_BENCH_THRESHOLD    as Number = 120; // bpm – HR below this → probably on bench
const ACCEL_ICE_THRESHOLD   as Number = 400; // mg  – wrist activity for skating
const ACCEL_BENCH_THRESHOLD as Number = 100; // mg  – wrist activity for sitting

// How long a condition must hold before a state change is committed.
// Accel rises/falls immediately; HR lags, so BENCH confirmation is longer.
const CONFIRM_ICE_MS        as Number = 8000;  // 8 s  – accel stays high → confirm on ice
const CONFIRM_BENCH_MS      as Number = 12000; // 12 s – accel stays low  → confirm on bench

// ── HRM-Pro chest strap: fast HR path ────────────────────────────────────────
// The HRM-Pro Plus is ECG-based → HR latency is 1–2 s (vs 15–30 s for optical).
// When HR is rising quickly AND accel is already high, we can confirm an
// ice entry much sooner than the default CONFIRM_ICE_MS would allow.
//
// HR_DELTA_FAST_BPM: minimum HR rise per second (averaged over 3 ticks)
//   that counts as a "running HR" confirmation.  With a chest strap this is
//   reliable; with optical it would be too noisy to use.
//
// CONFIRM_ICE_FAST_MS: shortened confirmation window used when BOTH accel
//   is above threshold AND HR is rising at ≥ HR_DELTA_FAST_BPM.

const HR_DELTA_FAST_BPM     as Number = 3;    // bpm/s – rising HR rate → on ice confirmed
const CONFIRM_ICE_FAST_MS   as Number = 3000; // 3 s  – fast path when HR co-confirms

// ── Fixed-capacity circular ring buffer ───────────────────────────────────────
// Used for HR (10 samples = 10 s) and accelerometer activity (25 samples = 1 s).

class RingBuffer {
    private var _buf  as Array<Number>;
    private var _cap  as Number;
    private var _head as Number;
    private var _size as Number;

    function initialize(capacity as Number) {
        _cap  = capacity;
        _head = 0;
        _size = 0;
        _buf  = new [_cap] as Array<Number>;
        for (var i = 0; i < _cap; i++) { _buf[i] = 0; }
    }

    function push(value as Number) as Void {
        _buf[_head] = value;
        _head = (_head + 1) % _cap;
        if (_size < _cap) { _size++; }
    }

    function average() as Number {
        if (_size == 0) { return 0; }
        var sum = 0;
        for (var i = 0; i < _size; i++) { sum += _buf[i]; }
        return sum / _size;
    }

    function count() as Number { return _size; }

    function reset() as Void {
        _head = 0;
        _size = 0;
        for (var i = 0; i < _cap; i++) { _buf[i] = 0; }
    }
}

// ── Individual shift record ────────────────────────────────────────────────────

class ShiftRecord {
    var startMs    as Number;
    var durationMs as Number;

    function initialize(start as Number, dur as Number) {
        startMs    = start;
        durationMs = dur;
    }
}

// ── Central data model ────────────────────────────────────────────────────────

class ShiftData {
    var shifts        as Array<ShiftRecord>; // completed shifts
    var breaks        as Array<Number>;      // break durations in ms
    var totalToiMs    as Number;             // cumulative time on ice
    var currentHR     as Number;             // latest HR reading (bpm)
    var currentAccel  as Number;             // latest activity level (mg deviation)
    var hrDelta       as Number;             // HR change per second (bpm/s, signed)
    var isSimulation  as Boolean;
    var goals         as Number;
    var assists       as Number;
    var simAvgHR      as Number;
    var simCals       as Number;
    var feelRating    as Number;   // 1-5: how did you play
    var effortRating  as Number;   // 1-5: perceived exertion

    function initialize() {
        shifts       = [] as Array<ShiftRecord>;
        breaks       = [] as Array<Number>;
        totalToiMs   = 0;
        currentHR    = 0;
        currentAccel = 0;
        hrDelta      = 0;
        isSimulation = false;
        goals        = 0;
        assists      = 0;
        simAvgHR     = 0;
        simCals      = 0;
        feelRating   = 0;
        effortRating = 0;
    }

    function addShift(startMs as Number, durationMs as Number) as Void {
        if (shifts.size() >= 50) {
            shifts = shifts.slice(1, null);
        }
        shifts.add(new ShiftRecord(startMs, durationMs));
        totalToiMs += durationMs;
    }

    function addBreak(durationMs as Number) as Void {
        if (breaks.size() >= 50) {
            breaks = breaks.slice(1, null);
        }
        breaks.add(durationMs);
    }

    function getShiftCount() as Number {
        return shifts.size();
    }

    function getLastShiftMs() as Number {
        if (shifts.size() == 0) { return 0; }
        return shifts[shifts.size() - 1].durationMs;
    }

    function getAvgShiftMs() as Number {
        if (shifts.size() == 0) { return 0; }
        var total = 0;
        for (var i = 0; i < shifts.size(); i++) {
            total += shifts[i].durationMs;
        }
        return total / shifts.size();
    }

    function getAvgBreakMs() as Number {
        if (breaks.size() == 0) { return 0; }
        var total = 0;
        for (var i = 0; i < breaks.size(); i++) {
            total += breaks[i];
        }
        return total / breaks.size();
    }

    function reset() as Void {
        shifts       = [] as Array<ShiftRecord>;
        breaks       = [] as Array<Number>;
        totalToiMs   = 0;
        goals        = 0;
        assists      = 0;
        simAvgHR     = 0;
        simCals      = 0;
    }

    // Format milliseconds as "M:SS"
    function msToStr(ms as Number) as String {
        var sec = ms / 1000;
        var min = sec / 60;
        sec     = sec % 60;
        return min.toString() + ":" + sec.format("%02d");
    }
}
