// ─── HockeyApp.mc ─────────────────────────────────────────────────────────────
// Application entry point.
//
// Sensor strategy:
//   1. Try the modern Sensor.registerSensorDataListener() API with raw
//      accelerometer at 25 Hz.  This is the full-fidelity path.
//   2. If that fails (very old CIQ firmware), fall back to the legacy
//      Sensor.enableSensorEvents() API which gives HR-only.
//
// Timing:
//   A 1-second repeating timer drives ShiftDetector.onTick() and
//   SimulationHelper.onTick(), then requests a UI redraw.
// ──────────────────────────────────────────────────────────────────────────────

import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Sensor;
import Toybox.Timer;
import Toybox.ActivityRecording;

class HockeyApp extends Application.AppBase {
    private var _data     as ShiftData;
    private var _detector as ShiftDetector;
    private var _sim      as SimulationHelper;
    private var _timer    as Timer.Timer or Null;
    private var _session  as ActivityRecording.Session or Null;

    function initialize() {
        AppBase.initialize();
        _data     = new ShiftData();
        _detector = new ShiftDetector(_data);
        _sim      = new SimulationHelper(_detector, _data);
    }

    function onStart(state as Dictionary?) as Void {
        // ── Start FIT activity recording ──────────────────────────────────────
        // This creates an Ice Hockey activity visible in Garmin Connect.
        try {
            var sessionOptions = {
                :name     => "Ice Hockey",
                :sport    => Activity.SPORT_HOCKEY,
                :subSport => Activity.SUB_SPORT_ICE
            };
            _session = ActivityRecording.createSession(sessionOptions);
            _session.start();
        } catch (ex instanceof Lang.Exception) {
            // FIT recording unavailable – continue without it
            _session = null;
        }

        // ── Register sensor listener with 25 Hz accelerometer ─────────────────
        var sensorOptions = {
            :period       => 1,
            :accelerometer => {
                :enabled    => true,
                :sampleRate => 25
            }
        };
        try {
            Sensor.registerSensorDataListener(method(:onSensorData), sensorOptions);
        } catch (ex instanceof Lang.Exception) {
            // Fallback: heart-rate only via legacy API
            Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE]);
            Sensor.enableSensorEvents(method(:onLegacySensor));
        }

        // ── 1-second tick timer ───────────────────────────────────────────────
        _timer = new Timer.Timer();
        _timer.start(method(:onTimerTick), 1000, true);
    }

    function onStop(state as Dictionary?) as Void {
        if (_timer != null) {
            _timer.stop();
        }

        // Unregister sensors – unregisterSensorDataListener() covers both
        // the modern batch API and the legacy enableSensorEvents() path.
        try {
            Sensor.unregisterSensorDataListener();
        } catch (ex instanceof Lang.Exception) { }

        // Save the FIT session
        if (_session != null && _session.isRecording()) {
            _session.stop();
            _session.save();
        }
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var view     = new HockeyView(_data, _detector);
        var delegate = new HockeyDelegate(_detector, _data, _sim);
        return [view, delegate];
    }

    // ── Sensor callbacks ──────────────────────────────────────────────────────

    function onSensorData(sensorData as Sensor.SensorData) as Void {
        if (!_sim.isActive()) {
            // Only process real sensor data when simulation is not running
            _detector.processSensorData(sensorData);
        }
    }

    function onLegacySensor(sensorInfo as Sensor.Info) as Void {
        if (!_sim.isActive()) {
            _detector.processLegacySensor(sensorInfo);
        }
    }

    // ── 1-second tick ─────────────────────────────────────────────────────────

    function onTimerTick() as Void {
        if (_sim.isActive()) {
            _sim.onTick();
        }
        _detector.onTick();
        WatchUi.requestUpdate();
    }
}

// Convenience accessor used by other modules if needed
function getApp() as HockeyApp {
    return Application.getApp() as HockeyApp;
}
