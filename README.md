# CHALLENGE
Build a Junior Astronaut Mission Trainer

Space-themed STEM content often oversimplifies the engineering trade-offs
that define a real mission or presents them at a level too complex to
hold a young learner's attention. Few tools make those trade-offs both
tangible and fun. Your challenge is to design and build an interactive
game or app that lets students run a lunar or Martian outpost, balancing
competing demands like life support, radiation shielding, power, and food
production, so they experience firsthand the decisions that determine
whether a mission fails or succeeds.

# MY SOLUTION — A Tamagotchi-Style Mars Outpost Survival Game (Godot 4.x)

**Core idea:** instead of a digital pet, the player keeps a Mars outpost
alive, using real NASA environmental data to drive daily threats. A small
creature mascot lives at the outpost and visibly reacts to how it's doing.

# Junior Astronaut Mission Trainer

A tamagotchi-style Mars outpost survival game built in **Godot 4.x**, made for
the NASA Space Apps Challenge: *Build a Junior Astronaut Mission Trainer*.

Instead of a digital pet, the player keeps a Mars outpost alive using real
NASA environmental data to drive daily threats. A small creature mascot lives
at the outpost and visibly reacts to how it's doing — one neglected system
drags the whole outpost (and the mascot's mood) down, which is the core
lesson: real missions live and die on competing trade-offs, not on any single
system in isolation.

> **Status:** in active development for Space Apps. This repo currently
> contains the core game logic and scripts; `mission_data.json` is still
> placeholder-shaped and is being replaced with parsed real mission data
> (see [Data Sources](#data-sources) below).

---

## Gameplay loop, per SOL (Martian day)

1. The game starts live on **SOL 1** — no idle intro screen. The player sees
   that SOL's real environmental readings (radiation dose, surface temp,
   sunlight hours) and four vitals, all starting at 100%: **Life Support**,
   **Power**, **Radiation Shield**, **Food Production**.
2. The player spends two shared resource pools — **Energy** and
   **Manpower** — on care actions (Repair Life Support, Boost Power,
   Reinforce Shield, Tend Food), each costing a different mix of both.
   - Energy is capped by current **Power**.
   - Manpower is capped by current **Life Support** (with a fatigue penalty
     below a threshold).
   - Both pools have a small guaranteed floor so a struggling outpost has
     *less* capacity to recover — the actual "competing demands" tension —
     without becoming completely un-recoverable.
3. Pressing **End Day** applies that SOL's real data as decay to the vitals,
   then shows a "SOL X CONSEQUENCES" panel: before → after numbers for all
   four vitals, plus an auto-generated plain-language cause line (e.g. *"Low
   sunlight reduced power generation. Reduced power also affected food
   production."*).
4. On notable data spikes (extreme radiation, cold, or darkness), a rarer
   "educational note" explains the real scientific phenomenon in
   kid-readable language.
5. A one-line **forecast** previews the next SOL's conditions in general
   terms (e.g. "expect elevated radiation") before the player commits their
   actions, so planning ahead is possible without spoiling the exact numbers.
6. The mascot's expression is driven by whichever vital is currently
   **worst**, not the average.
7. A once-per-mission **Emergency Protocol** fully restores the worst vital
   at a moderate cost to the others — a safety valve so one bad SOL can't
   compound into an unrecoverable spiral before the player can react.
8. The mission ends in **SUCCESS** (survived the full real dataset) or
   **FAILURE** (any vital hit 0%), followed by a debrief screen: final
   vitals, days survived, and the real NASA data sources cited by name.

---

## File structure

```
res://
├── data/
│   └── mission_data.json        # Sol-by-sol real data (see schema below)
├── scripts/
│   ├── DataLoader.gd            # Autoload — loads mission_data.json, exposes get_day(n) / total_days()
│   ├── StatsManager.gd          # Autoload — core game logic (see below)
│   ├── OutpostUI.gd             # Main scene controller — wires UI to StatsManager signals
│   └── CharacterPortrait.gd     # Mascot controller — worst-vital-driven expression
└── scenes/
    └── Outpost.tscn             # Main scene, mobile portrait layout (1080×1920 reference resolution)
        Control (root, OutpostUI.gd)
        ├── Background (TextureRect)
        ├── CharacterPortrait (Control, CharacterPortrait.gd)
        │   ├── ModelHolder (Control) → ModelSprite (AnimatedSprite2D)
        │   └── FaceLabel (Label, emoji fallback until sprite animations exist)
        ├── VBoxContainer
        │   ├── DayLabel, ConsequencesLabel, MissionLogLabel, NoteLabel (Labels)
        │   ├── ForecastLabel (Label, optional — see "Optional nodes" below)
        │   ├── LifeSupportRow / PowerRow / RadiationRow / FoodRow
        │   │     (each: Control wrapping a TextureProgressBar + overlay Label)
        │   ├── ResourcesLabel (Label)
        │   ├── Actions (HBoxContainer) → 4 icon+text Buttons
        │   ├── EmergencyButton (Button, optional — see "Optional nodes" below)
        │   └── EndDayButton (TextureButton)
        └── DebriefPanel (PanelContainer, full-screen overlay)
            └── DebriefVBox → DebriefLabel, RestartButton
```

### What each script owns

| Script | Role |
|---|---|
| `DataLoader.gd` | Loads `mission_data.json` once at startup. Carries the last known real value forward across data gaps (flagging the day as `is_gap_filled`) instead of silently defaulting. Returns `{}` past the end of the dataset — **this must not clamp**, or the mission never reaches the success screen. |
| `StatsManager.gd` | Owns the four vitals, the Energy/Manpower pools (derived from current Power/Life Support), daily decay math, the cause-line and educational-note generation, the forecast line, the Emergency Protocol, and mission success/failure + debrief text. |
| `OutpostUI.gd` | Wires every UI element to `StatsManager`'s signals. Reads all nodes via `%UniqueName` (see setup below), with explicit asserts naming any missing node at startup. |
| `CharacterPortrait.gd` | Drives the mascot's expression from whichever vital is currently worst, with an emoji fallback until sprite-sheet animations exist for a state. |

---

## Setup (Godot 4.x)

1. **Register the autoloads.** In *Project Settings → Autoload*, add:
   - `DataLoader.gd` → name it `DataLoader`
   - `StatsManager.gd` → name it `StatsManager`

   Both scripts must be added as autoloads (singletons), not attached to a
   scene node — `OutpostUI.gd` and `CharacterPortrait.gd` reference them
   globally (`DataLoader.get_day(...)`, `StatsManager.perform_action(...)`).

2. **Enable "Access as Unique Name" on every required node.** `OutpostUI.gd`
   and `CharacterPortrait.gd` reference nodes via `%NodeName` rather than
   `$DeepPath`, so a node can be moved without breaking the reference. For
   each node listed in the file structure above (all bars, bar labels, the
   four action buttons, End Day button, all report/consequences/note labels,
   the debrief panel/label/restart button, and the three portrait nodes:
   `ModelSprite`, `FaceLabel`, `ModelHolder`) — right-click the node in the
   Scene panel → **Access as Unique Name**, then save the scene.

   If a required node isn't flagged, the game fails loudly at launch with
   an assert naming the exact missing node, rather than crashing silently
   later the first time that node is touched.

3. **Optional nodes.** Two features are wired defensively and simply stay
   inactive if their node isn't present — no code changes needed either way:
   - `ForecastLabel` (a `Label`) — shows the next-SOL forecast line.
   - `EmergencyButton` (a `Button`) — triggers the once-per-mission
     Emergency Protocol.

   Add either anywhere under `VBoxContainer`, flag it as a unique name, and
   it activates automatically.

4. **Run the main scene** (`Outpost.tscn`). `OutpostUI._ready()` connects to
   `StatsManager`'s signals and then calls `StatsManager.start_mission()`,
   which emits the SOL 1 morning report.

### Known gotchas

- **Node naming mismatches fail loudly now, not silently.** Every required
  node lookup is asserted at startup with the exact missing node's name —
  if you see an assertion failure, it's telling you exactly which node
  needs "Access as Unique Name" enabled (or was renamed/deleted).
- **`TextureProgressBar` has no built-in text.** Vital percentages are shown
  via a separate overlay `Label` per bar (e.g. `LifeSupportBarLabel`), kept
  in sync from `StatsManager.stats_changed`.
- **`TextureButton` vs `Button` type mismatches** — `EndDayButton` is a
  `TextureButton`; the four action buttons are plain `Button`s. Don't swap
  these types without updating the corresponding `@onready var` type in
  `OutpostUI.gd`.
- **`DataLoader.get_day()` must not clamp to the last day.** `StatsManager`
  relies on an empty dict from `get_day(current_day + 1)` to detect mission
  completion; clamping would make the mission repeat the final SOL forever.

---

## `mission_data.json` schema

```json
{
  "location": "Jezero Crater, Mars (temperature/sunlight) + Gale Crater, Mars (radiation)",
  "radiation_source": "MSL/RAD Level 3 RDR — PDS Planetary Plasma Interactions Node",
  "temperature_source": "Mars 2020/MEDA Air Temperature Sensor — derived dataset (Hueso et al. 2024, Zenodo)",
  "sunlight_note": "Estimated from atmospheric conditions; not a direct instrument measurement",
  "source_notes": "Combines two rovers at two different landing sites into one simulated outpost.",
  "days": [
    {
      "date": "SOL 1",
      "radiation_dose_rate": 0.42,
      "surface_temp_c": -78.0,
      "sunlight_hours": 12.3
    }
  ]
}
```

- `radiation_dose_rate`, `surface_temp_c`, and `sunlight_hours` may be `null`
  for a given day; `DataLoader` carries the last known value forward and
  marks that day `is_gap_filled: true` for display.
- `radiation_source` / `temperature_source` / `sunlight_note` are optional
  but recommended — if present, they're shown individually on the debrief
  screen; if absent, the debrief falls back to the combined `location` /
  `source_notes` fields.

---

## Data sources

Real NASA (and space-agency-partner) mission data drives every day's decay:

| Variable | Instrument / Mission | Node / Archive |
|---|---|---|
| Radiation dose | RAD (Radiation Assessment Detector) / Curiosity, MSL | PDS Planetary Plasma Interactions Node — `MSL-M-RAD-3-RDR-V1.0` |
| Surface temperature | MEDA (Mars Environmental Dynamics Analyzer) Air Temperature Sensor / Perseverance, Mars 2020 | PDS Atmospheres Node; derived table via Hueso et al. (2024), Zenodo DOI `10.5281/zenodo.11198655` |
| Pressure (context data) | Multi-mission Mars surface pressure corpus | Zenodo |

Because these come from two rovers at two different craters and mission
timelines, days are aligned **by sol number**, not by real Earth calendar
date — this is disclosed on the debrief screen rather than implied to be one
continuous real-time feed.

---

## Supporting docs (not part of the Godot project)

- `SETUP.md` — full build/setup reference: autoload registration, node
  tree, asset specs, data sources, known gotchas.
- `video1-script.md` — 240-second prescreening pitch video script.

---

## Roadmap / open items

- [ ] Replace placeholder `mission_data.json` with real parsed MEDA/RAD/
      pressure values.
- [ ] Add sprite-sheet animations for the six mascot states (currently
      falls back to emoji).
- [ ] Playtest balance from a deliberately neglected starting state, not
      only from 100% vitals.
