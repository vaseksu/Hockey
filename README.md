# Hockey Shifts – Garmin Connect IQ App

Ice hockey shift tracker for **Garmin Fenix 8 AMOLED 51mm** (and compatible Fenix 8 / Solar variants).

## What it tracks

| Field | Description |
|---|---|
| **State** | ON ICE / BENCH / transitioning |
| **Current timer** | How long you've been in the current state |
| **Shift count** | Total number of shifts completed |
| **Total TOI** | Cumulative time on ice |
| **Avg shift** | Mean shift duration |
| **Last shift** | Duration of most recent shift |

The session is also saved as an **Ice Hockey** FIT activity in Garmin Connect.

---

## Detection algorithm

```
Accel (primary)   ──►  State machine  ──►  ShiftData
HR (display/log)         │
                         ▼
                  ON_BENCH / ON_ICE
```

**Why accelerometer-first?**  
Accel changes *instantly* when you step on/off the ice.  
HR lags 30–60 s getting on ice, and stays elevated 60–90 s after sitting down — making it unsuitable as a primary trigger.

### Thresholds (in `source/ShiftData.mc`)

| Constant | Default | Meaning |
|---|---|---|
| `ACCEL_ICE_THRESHOLD` | 400 mg | Wrist movement above this → skating |
| `ACCEL_BENCH_THRESHOLD` | 100 mg | Wrist movement below this → seated |
| `HR_ICE_THRESHOLD` | 145 bpm | Reference from your activity (peak 191) |
| `HR_BENCH_THRESHOLD` | 120 bpm | Reference from your activity (min 82) |
| `CONFIRM_ICE_MS` | 8 000 ms | Hold accel high this long → confirm on ice |
| `CONFIRM_BENCH_MS` | 12 000 ms | Hold accel low this long → confirm on bench |

> **Tuning tip**: After your first real session, look at the HR + accel chart in Garmin Connect or export the FIT file. Adjust the `ACCEL_*` constants first — they are the most impactful.

---

## Button mapping (Fenix 8)

| Button | Action |
|---|---|
| **SELECT** (short press) | Manual shift toggle (override auto-detection) |
| **UP / MENU** (long press) | Opens settings menu |
| **BACK** (long press) | Stop & save activity |

---

## Building

### Prerequisites
1. [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) 4.2.0+
2. VS Code with the **Monkey C** extension, OR use `monkeyc` CLI

### Build via CLI
```sh
monkeyc -f monkey.jungle -o bin/hockey.prg -y developer_key.der -d fenix8Amoled51mm
```

### Launcher icon
Add a **70 × 70 px** PNG as `resources/drawables/launcher_icon.png` and uncomment the line in `resources/drawables/drawables.xml` before publishing to the Connect IQ Store.

---

## Testing without skating

### 1 – Connect IQ Simulator (primary method)

Open the project in VS Code with the Monkey C extension:
- Run → **Run Without Debugging** → select `fenix8Amoled51mm`
- The simulator opens with a virtual 454×454 watch
- Use **Simulation > Sensors** to manually set HR and accelerometer values

### 2 – Built-in simulation mode (best for algorithm testing)

On the simulator (or real watch):
1. Long-press UP → **Run simulation**
2. The app replays a ~7-minute synthetic hockey excerpt:
   - bench 15 s → shift 40 s → bench 90 s → shift 38 s → bench 90 s → shift 42 s → bench
3. HR is linearly ramped (realistic physiology); accel changes instantly
4. Watch the state machine trigger shifts automatically — verify timings and UI

The simulation drives the **same code path** as real sensors via `ShiftDetector.injectData()`, so every detection branch is exercised identically.

### 3 – Replay your own FIT file

Export activity `23009826047` as a FIT file from Garmin Connect, then use the **FIT SDK** to extract HR and timestamp arrays and feed them into a local Monkey C unit test harness. This lets you replay an entire real game to validate thresholds.

### 4 – Proxy physical test

If you want real sensor data:
- Do 30 s of jumping jacks / burpees (raises HR + accel simultaneously)
- Sit still for 2 min
- Repeat 3–4 times to simulate shift rhythm
- Adjust thresholds based on what fires

---

## File structure

```
Hockey/
├── manifest.xml             App manifest (UUID, permissions, target devices)
├── monkey.jungle            Build configuration
├── source/
│   ├── ShiftData.mc         Data model, constants, RingBuffer helper
│   ├── ShiftDetector.mc     State machine (the core algorithm)
│   ├── SimulationHelper.mc  Synthetic data injector for testing
│   ├── HockeyView.mc        Watch face renderer (454×454 AMOLED)
│   ├── HockeyDelegate.mc    Button / menu input handling
│   └── HockeyApp.mc         App entry, sensor registration, FIT session
└── resources/
    ├── strings/strings.xml
    └── drawables/drawables.xml
```

---

## Roadmap / future ideas

- [ ] Export per-shift data as FIT custom fields (lap records per shift)
- [ ] Configurable thresholds via in-app settings page
- [ ] Buzzer/vibration alert when a shift exceeds a target duration
- [ ] Respiration rate as a third confirmation signal (available on your activity)
- [ ] Period tracking (1st / 2nd / 3rd + overtime)
