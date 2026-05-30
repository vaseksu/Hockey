// ─── ShiftDetector.mc ─────────────────────────────────────────────────────────
// State machine that drives the on-ice / on-bench detection.
//
// Signal strategy
// ───────────────
// Accelerometer is the PRIMARY trigger:
//   • It reacts instantly when you step onto the ice and start skating.
//   • It drops instantly the moment you sit on the bench.
//
// HRM-Pro Plus chest strap (ECG) is a SECONDARY co-trigger:
//   • ECG latency is ~1–2 s, vs 15–30 s for wrist optical.
//   • When accel is already high AND HR is rising ≥ HR_DELTA_FAST_BPM/s,
//     the ice-entry confirmation window shrinks from 8 s to 3 s.
//   • Wrist optical HR is too noisy and laggy to co-trigger safely, so
//     the fast path only activates when HR is actually changing quickly
//     (which wrist optical simply cannot do in under 5 s).
//   For BENCH confirmation we still rely purely on accel — HR stays
//   elevated for 60–90 s even with a chest strap after exertion stops.
//
// State machine
// ─────────────
//   ON_BENCH ──[accel rises]──► GOING_ON_ICE ──[held 8 s]──► ON_ICE
//                                     │                          │
//                             [accel drops]               [accel drops]
//                                     │                          │
//                                     ▼                          ▼
//                                 ON_BENCH        GOING_TO_BENCH ──[held 12 s]──► ON_BENCH
//                                                       │
//                                               [accel rises]
//                                                       │
//                                                       ▼
//                                                    ON_ICE
// ──────────────────────────────────────────────────────────────────────────────

import Toybox.Activity;
import Toybox.Lang;
import Toybox.System;
import Toybox.Sensor;
import Toybox.Math;

const STATE_BENCH          as Number = 0;
const STATE_GOING_ON_ICE   as Number = 1;
const STATE_ON_ICE         as Number = 2;
const STATE_GOING_TO_BENCH as Number = 3;

class ShiftDetector {
    private var _data               as ShiftData;
    private var _state              as Number;
    private var _stateEnteredMs     as Number;
    private var _shiftStartMs       as Number;
    private var _benchStartMs       as Number;
    private var _transitionStartMs  as Number;

    // Rolling window buffers
    private var _hrBuf    as RingBuffer; // 10-second HR average (one push per second)
    private var _accelBuf as RingBuffer; // 1-second accel average (25 pushes @ 25 Hz)

    // HR rate-of-change tracking (for HRM-Pro fast path)
    private var _prevHR       as Number; // HR value from the previous tick
    private var _hrDeltaBuf   as RingBuffer; // 3-sample rolling window of (hr - prevHR)

    function initialize(data as ShiftData) {
        _data = data;

        var now            = System.getTimer();
        _state             = STATE_BENCH;
        _stateEnteredMs    = now;
        _shiftStartMs      = now;
        _benchStartMs      = now;
        _transitionStartMs = now;

        _hrBuf      = new RingBuffer(10);
        _accelBuf   = new RingBuffer(25);
        _hrDeltaBuf = new RingBuffer(3);
        _prevHR     = 0;
    }

    // ── Public accessors ──────────────────────────────────────────────────────

    function getState() as Number { return _state; }

    // How long we have been in the current state (ms)
    function getCurrentDurationMs() as Number {
        return System.getTimer() - _stateEnteredMs;
    }

    // ── Main tick – called every second from the app timer ────────────────────

    function onTick() as Void {
        var now   = System.getTimer();
        var accel = _accelBuf.average();

        // Poll HR every tick so the display stays fresh even in the simulator
        // where the sensor callback may not deliver HR.
        // Priority: simulation injection > ActivityInfo > Sensor.getInfo()
        if (!_data.isSimulation) {
            var gotHR = false;
            var actInfo = Activity.getActivityInfo();
            if (actInfo != null && actInfo.currentHeartRate != null) {
                var hr = actInfo.currentHeartRate as Number;
                _hrBuf.push(hr);
                _data.currentHR = hr;
                gotHR = true;
            }
            if (!gotHR) {
                var sInfo = Sensor.getInfo();
                if (sInfo != null && sInfo.heartRate != null) {
                    var hr = sInfo.heartRate as Number;
                    _hrBuf.push(hr);
                    _data.currentHR = hr;
                }
            }
        }

        // Update HR delta buffer (push current tick's change from last tick)
        if (_prevHR > 0 && _data.currentHR > 0) {
            _hrDeltaBuf.push(_data.currentHR - _prevHR);
            _data.hrDelta = _hrDeltaBuf.average();
        }
        _prevHR = _data.currentHR;

        if (_state == STATE_BENCH) {
            if (accel >= ACCEL_ICE_THRESHOLD) {
                _transitionStartMs = now;
                _enterState(STATE_GOING_ON_ICE, now);
            }

        } else if (_state == STATE_GOING_ON_ICE) {
            if (accel >= ACCEL_ICE_THRESHOLD) {
                // Fast path: HRM-Pro ECG is rising strongly → confirm in 3 s
                // Normal path: accel alone, confirm in 8 s
                var hrRising      = _data.hrDelta >= HR_DELTA_FAST_BPM;
                var requiredMs    = hrRising ? CONFIRM_ICE_FAST_MS : CONFIRM_ICE_MS;
                if (now - _transitionStartMs >= requiredMs) {
                    // Confirmed on ice: record break, start shift clock
                    _data.addBreak(now - _benchStartMs);
                    _shiftStartMs = now;
                    _enterState(STATE_ON_ICE, now);
                }
            } else {
                // Movement stopped before confirmation – false alarm
                _enterState(STATE_BENCH, now);
            }

        } else if (_state == STATE_ON_ICE) {
            if (accel < ACCEL_BENCH_THRESHOLD) {
                _transitionStartMs = now;
                _enterState(STATE_GOING_TO_BENCH, now);
            }

        } else if (_state == STATE_GOING_TO_BENCH) {
            if (accel < ACCEL_BENCH_THRESHOLD) {
                if (now - _transitionStartMs >= CONFIRM_BENCH_MS) {
                    // Confirmed on bench: record completed shift
                    _data.addShift(_shiftStartMs, now - _shiftStartMs);
                    _benchStartMs = now;
                    _enterState(STATE_BENCH, now);
                }
            } else {
                // Movement resumed – still on ice (stoppage, faceoff, etc.)
                _enterState(STATE_ON_ICE, now);
            }
        }
    }

    // ── Process raw sensor batch (Sensor.SensorData – modern API) ─────────────

    function processSensorData(sensorData as Sensor.SensorData) as Void {
        // Heart rate: SensorData does not expose HR directly in SDK 8.x.
        // Read it from ActivityInfo which is updated every second.
        var actInfo = Activity.getActivityInfo();
        if (actInfo != null && actInfo.currentHeartRate != null) {
            var hr = actInfo.currentHeartRate as Number;
            _hrBuf.push(hr);
            _data.currentHR = hr;
        }

        // Accelerometer: compute per-sample deviation from 1 g
        var ad = sensorData.accelerometerData;
        if (ad != null) {
            var xs = ad.x;
            var ys = ad.y;
            var zs = ad.z;
            if (xs != null && xs.size() > 0) {
                _computeAccelActivity(xs as Array<Number>,
                                      ys as Array<Number>,
                                      zs as Array<Number>);
            }
        }
    }

    // ── Legacy fallback for older sensor API ──────────────────────────────────

    function processLegacySensor(info as Sensor.Info) as Void {
        if (info.heartRate != null) {
            var hr = info.heartRate as Number;
            _hrBuf.push(hr);
            _data.currentHR = hr;
        }
        // Legacy API does not expose raw accelerometer samples;
        // the state machine will continue to work from HR alone but
        // transition accuracy will be reduced.
    }

    // ── Manual override via Select button ─────────────────────────────────────
    // Allows the player to mark a transition that the algorithm missed.

    function manualToggle() as Void {
        var now = System.getTimer();
        if (_state == STATE_ON_ICE || _state == STATE_GOING_ON_ICE) {
            if (_state == STATE_ON_ICE) {
                _data.addShift(_shiftStartMs, now - _shiftStartMs);
            }
            _benchStartMs = now;
            _enterState(STATE_BENCH, now);
        } else {
            _data.addBreak(now - _benchStartMs);
            _shiftStartMs = now;
            _enterState(STATE_ON_ICE, now);
        }
    }

    // ── Simulation injection ──────────────────────────────────────────────────
    // SimulationHelper calls this instead of processSensorData.

    function injectData(hr as Number, accel as Number) as Void {
        _hrBuf.push(hr);
        _accelBuf.push(accel);
        _data.currentHR    = hr;
        _data.currentAccel = accel;
        // hrDelta is computed in onTick() from _prevHR vs currentHR
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private function _enterState(newState as Number, now as Number) as Void {
        _state          = newState;
        _stateEnteredMs = now;
    }

    private function _computeAccelActivity(xs as Array<Number>,
                                            ys as Array<Number>,
                                            zs as Array<Number>) as Void {
        var n = xs.size();
        for (var i = 0; i < n; i++) {
            var xf  = xs[i].toFloat();
            var yf  = ys[i].toFloat();
            var zf  = zs[i].toFloat();
            // Magnitude of acceleration vector (mg)
            var mag = Math.sqrt(xf * xf + yf * yf + zf * zf).toNumber();
            // Activity level = deviation from 1 g (1000 mg).
            // At rest this is near zero; skating swings it to 400–1000+.
            var dev = mag - 1000;
            if (dev < 0) { dev = -dev; }
            _accelBuf.push(dev);
        }
        _data.currentAccel = _accelBuf.average();
    }
}
