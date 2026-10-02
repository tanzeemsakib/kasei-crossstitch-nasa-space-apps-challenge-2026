# Junior Astronaut Mission Trainer — *Kasei*

## Challenge

**Build a Junior Astronaut Mission Trainer**

Space-themed STEM content often oversimplifies the engineering trade-offs
that define a real mission or presents them at a level too complex to
hold a young learner's attention. Few tools make those trade-offs both
tangible and fun. Your challenge is to design and build an interactive
game or app that lets students run a lunar or Martian outpost, balancing
competing demands like life support, radiation shielding, power, and food
production, so they experience firsthand the decisions that determine
whether a mission fails or succeeds.

## Our solution

A **tamagotchi-style Mars outpost survival game** built in **Godot 4.x**.
Instead of a digital pet, the player keeps a Mars outpost alive using real
NASA environmental data to drive daily threats. A small creature mascot,
**Kasei**, lives at the outpost and visibly reacts to how it's doing — one
neglected system drags the whole outpost (and the mascot's mood) down,
which is the core lesson: real missions live and die on competing
trade-offs, not on any single system in isolation.

> **Status:** in active development for Space Apps. Radiation decay is now
> driven by **real MSL/RAD data** (see [Data sources](#data-sources)).
> Temperature and sunlight are still placeholder-shaped in
> `mission_data.json`, pending a second real dataset.

**Play it in the browser:** https://tanzeemsakib.github.io/kasei-crossstitch-nasa-space-apps-challenge-2026/

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
3. Pressing **End Day** applies that SOL's real data as decay to the vitals.
   The left telemetry panel stays always-current rather than showing a
   separate before/after breakdown — watch the numbers change as you spend
   actions and end the day. An auto-generated plain-language cause line
   appears in the panel's alerts section (e.g. *"Low sunlight reduced power
   generation. Reduced power also affected food production."*).
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
8. A one-level **Undo** reverses the player's most recent action within the
   current sol (refunding its Energy/Manpower cost), cleared once End Day
   is pressed.
9. An **Info** popup shows each action's Energy/Manpower cost as a static
   reference, floating from the Info icon rather than taking over the
   screen.
10. An **"Ask Kasei"** chat panel answers a fixed set of preset questions
    (e.g. *"Why is my Radiation Shield low?"*) grounded in the live dataset
    and vitals — deliberately not a free-text/LLM chatbot, so every answer
    is deterministic and traceable back to real data (see
    `AssistantEngine.gd`).
11. A **history chart** plots all four vitals sol-by-sol as the mission
    progresses, so trends — not just a single day's snapshot — are visible.
12. The mission ends in **SUCCESS** (survived the full real dataset) or
    **FAILURE** (any vital hit 0%), followed by a debrief screen: final
    vitals, days survived, and the real NASA data sources cited by name.

---

## Visual design

The UI is built from a Figma mockup on a fixed **1080×1920** portrait
canvas, using a deliberately small, consistent palette:

| Role | Hex |
|---|---|
| Background | `#F8E9E9` |
| Fill (buttons, bars) | `#A070A1` |
| Text / borders | `#724060` |

Telemetry text uses **Space Mono** for a technical/readout feel. The
four history-chart lines are distinguished by **line style** (solid /
dashed / dotted / dash-dot), not color — everything stays within the
3-color palette rather than introducing chart-specific hues.

The game uses **Project Settings → Display → Window → Stretch → Mode:
`canvas_items`, Aspect: `keep`**, so the fixed-resolution layout scales as
one unit to fit any actual browser window instead of individual elements
drifting independently.

---

## File structure

```
res://
├── data/
│   └── mission_data.json        # Sol-by-sol data — radiation is REAL (see schema below)
├── scripts/
│   ├── DataLoader.gd            # Autoload — loads mission_data.json, exposes get_day(n) / total_days()
│   ├── StatsManager.gd          # Autoload — core game logic (see below)
│   ├── OutpostUI.gd             # Main scene controller — wires UI to StatsManager signals
│   ├── CharacterPortrait.gd     # Mascot controller — worst-vital-driven expression
│   ├── AssistantEngine.gd       # "Ask Kasei" chat — fixed Q&A over live mission data
│   └── HistoryChart.gd          # Dependency-free line-graph canvas (Control._draw())
└── scenes/
    └── Outpost.tscn             # Main scene, 1080×1920 reference resolution
        Control (root, OutpostUI.gd)
        ├── Background (TextureRect)
        ├── KASEILogo (Label — title text, no image asset)
        ├── ChartButton (TextureButton, top-left — opens the history chart)
        ├── ChatButton (TextureButton, top-right — opens "Ask Kasei")
        ├── TelemetryPanel (PanelContainer, bordered, Content Margin padded)
        │   └── TelemetryVBox (VBoxContainer, Space Mono font override)
        │       ├── DayLabel        — header: SOL / date / location
        │       ├── ConsequencesLabel — hidden (.visible = false); breakdown
        │       │     logic kept but not surfaced in this layout
        │       ├── MissionLogLabel — the always-current telemetry dashboard
        │       └── NoteLabel       — alerts: cause line + educational note + forecast
        ├── CharacterPortraitPanel (Panel, border only, matches TelemetryPanel)
        ├── CharacterPortrait (Control, CharacterPortrait.gd — the REACTIVE mascot)
        │   ├── ModelHolder (Control) → ModelSprite (AnimatedSprite2D)
        │   └── FaceLabel (Label, emoji fallback until sprite animations exist)
        ├── StaticPortraitPanel (Panel, border only)
        ├── StaticPortrait (TextureRect, no script — decorative headshot only)
        ├── VBoxContainer (vitals bars — bars only, nothing else)
        │   ├── LifeSupportBar / PowerBar / RadiationBar / FoodBar
        │   │     (each: TextureProgressBar + overlay Label, font color #F8E7E7)
        ├── ResourcesPanel (PanelContainer, border) → ResourcesLabel
        ├── Actions (HBoxContainer) → 4 TextureButtons (icon-only, no caption
        │     text — costs shown via tooltip_text and the Info popup instead)
        ├── EndDayButton (TextureButton — "END DAY" baked into the art)
        ├── InfoButton (TextureButton) / InfoPanel (PanelContainer, floats
        │     near the button, left-aligned, no close button — tap again to
        │     dismiss) → InfoVBox → InfoTitleLabel, InfoContentLabel (filled
        │     at _ready() from ACTION_TOOLTIPS)
        ├── UndoButton (TextureButton — one-level undo, disabled until an
        │     action is taken and again once End Day is pressed)
        ├── ChatPanel (PanelContainer, bottom sheet, no close button)
        │   └── ChatVBox → ChatTitleLabel, ChatResponseLabel,
        │         ScrollContainer → ChatQuestionsContainer (filled at
        │         runtime with one Button per AssistantEngine.QUESTIONS entry)
        ├── ChartPanel (PanelContainer, bottom sheet, no close button)
        │   └── ChartVBox → ChartTitleLabel, ChartCanvas (HistoryChart.gd),
        │         ChartLegendLabel (static text)
        └── DebriefPanel (PanelContainer, full-screen overlay)
            └── DebriefVBox → DebriefLabel, RestartButton
```

A shared **Theme** resource is assigned to the root `Control` node, styling
the base `Button` and `VScrollBar` types in the palette above — this is
what styles the runtime-generated chat question buttons too, since they
don't exist in the scene file to style individually.

### What each script owns

| Script | Role |
|---|---|
| `DataLoader.gd` | Loads `mission_data.json` once at startup. Carries the last known real value forward across data gaps (flagging the day as `is_gap_filled`), and falls back to an explicit numeric default when there's no prior value to carry forward at all — never leaves a field as JSON `null` (see Known Gotchas). Returns `{}` past the end of the dataset — **this must not clamp**, or the mission never reaches the success screen. |
| `StatsManager.gd` | Owns the four vitals, the Energy/Manpower pools, daily decay math, the cause-line and educational-note generation, the forecast line, the Emergency Protocol, one-level Undo, sol-by-sol history tracking (for the chart), and mission success/failure + debrief text. |
| `OutpostUI.gd` | Wires every UI element to `StatsManager`'s signals. Reads all nodes via `%UniqueName`, with explicit asserts naming any missing required node at startup. Also derives the telemetry panel's flavor readouts (interior temp, oxygen, CO2, water, food-reserve days, solar input%) from the four real vitals — see [Telemetry panel](#telemetry-panel-real-data-vs-derived-flavor). |
| `CharacterPortrait.gd` | Drives the mascot's expression from whichever vital is currently worst, with an emoji fallback until sprite-sheet animations exist for a state. |
| `AssistantEngine.gd` | "Ask Kasei" — a small, fixed set of preset questions answered from the live dataset and vitals. Deliberately not a free-text/LLM chatbot. Instantiated once by `OutpostUI`, not an autoload. |
| `HistoryChart.gd` | A minimal line-graph `Control` drawn with `_draw()` — no plugin, no external library. Draws solid/dashed/dotted/dash-dot lines from pre-normalized (0..1) series handed to it by `OutpostUI`; knows nothing about vitals or units itself. |

---

## Setup (Godot 4.x)

1. **Register the autoloads** (*Project Settings → Autoload*): `DataLoader.gd`
   as `DataLoader`, `StatsManager.gd` as `StatsManager`.
2. **Enable "Access as Unique Name"** on every node `OutpostUI.gd` /
   `CharacterPortrait.gd` reference via `%NodeName` — a missing one fails
   loudly at startup naming the exact node, rather than crashing silently
   later.
3. **Assign a Theme resource** to the root `Control` node, styling the
   `Button` and `VScrollBar` types in the palette above (needed for the
   runtime-generated chat questions to render correctly).
4. **Space Mono font**: download from Google Fonts, apply via Theme
   Overrides → Fonts on `TelemetryVBox` (inherited by its children), with
   Autowrap Mode = Word on each label.
5. Run `Outpost.tscn`. `OutpostUI._ready()` connects to `StatsManager`'s
   signals, then calls `StatsManager.start_mission()`.

### Exporting for the web (GitHub Pages)

1. Install Web export templates, add a Web preset (*Project → Export*).
2. **Uncheck "Thread Support"** in the Web preset options — plain GitHub
   Pages can't send the COOP/COEP headers a threaded build needs, and this
   avoids requiring them at all.
3. Export straight into a folder named **`docs`** at the repo root (GitHub
   Pages only offers `/ (root)` or `/docs` as a Pages source).
4. Rename the exported `.html` file to **`index.html`** — GitHub Pages only
   auto-serves a file with that exact name.
5. In GitHub: *Settings → Pages → Source* → your branch, `/docs` folder.
6. Push via `git` (not the website's drag-and-drop uploader) if any
   exported file exceeds 25 MB — e.g. the `.wasm` file. Browser uploads cap
   at 25 MB; `git push` allows up to 100 MB per file.

### Known gotchas

- **Node naming mismatches fail loudly, not silently.** Every required
  node lookup is asserted at startup with the exact missing node's name.
- **Draw order = click priority.** A `Control` node drawn later in the
  scene tree also *intercepts input* first — an icon button placed before
  a large sibling container can become unclickable even though it's
  visible. Icon-only overlay buttons (Chat/Chart/Info/Undo) and their
  panels need to sit near the *end* of the root `Control`'s child list.
- **A `Container`'s own Size can't go below its children's minimum size.**
  If a `TextureButton` inside an `HBoxContainer` still has a leftover
  `Custom Minimum Size` from before it was reparented, the container will
  silently refuse to shrink below that — clear each child's Custom Minimum
  Size to 0 and use Container Sizing (Fill/Expand) instead of fighting it.
- **`TextureButton` has no `.text` property.** Converting a `Button` with
  caption text (like the four action buttons originally had) drops the
  caption with no error — either bake the caption into the texture, add a
  separate overlay `Label`, or rely on `tooltip_text` / a popup instead
  (what this project does — see `ACTION_TOOLTIPS`).
- **`Dictionary.get(key, default)` does NOT apply `default` when the key
  exists with an explicit `null` value** — only when the key is *missing*
  entirely. A JSON field explicitly set to `null` (like the current
  placeholder `surface_temp_c`) will crash a typed float read if any code
  relies on `.get()`'s default to catch it. `DataLoader.gd` now resolves
  this centrally so no `null` ever leaves `get_day()` — see
  `FIELD_FALLBACK_DEFAULTS`.
- **`DataLoader.get_day()` must not clamp to the last day** — `StatsManager`
  relies on an empty dict from `get_day(current_day + 1)` to detect mission
  completion.

---

## Telemetry panel: real data vs. derived flavor

The left telemetry panel shows more readouts than `StatsManager` tracks as
separate stats. Rather than inventing untracked state, the extra readouts
are **derived directly from the four real vitals** in `OutpostUI.gd` — see
`_derived_interior_temp()` and its neighbors. This keeps every number on
screen honestly tied to either real mission data or real game state.

| Panel line | Source |
|---|---|
| SOL / date / location | Real — `current_day`, `day_data.date`, `DataLoader.location` |
| Surface temperature | Real — `surface_temp_c` |
| Interior temperature | Derived from `life_support` |
| Radiation dose | **Real — `radiation_dose_rate`, from actual MSL/RAD data** |
| Shield integrity | Real — `stats.radiation_shield` |
| Solar input % | Derived from `sunlight_hours` |
| Battery reserve | Real — `stats.power`, relabeled |
| Sunlight remaining | Real — `sunlight_hours` |
| Oxygen % | Derived from `life_support` |
| CO2 level | Derived, inverse of `life_support` |
| Water reserve | Derived from `food_production` |
| Food reserve (days) | Derived from `food_production` |
| Crew available | Real — `manpower_remaining` / `MAX_MANPOWER` |
| Alert lines | Cause line + educational note + forecast, combined by `_refresh_alerts_block()` |

Deliberately **not shown**: a fabricated local-time clock. There's no real
local-time data in the dataset to back one.

---

## `mission_data.json` schema

```json
{
  "location": "Gale Crater, Mars (radiation) — temperature/sunlight pending",
  "radiation_source": "MSL/RAD E-detector dose rate, notch-filtered, sol-averaged (Heber & Löwe 2026, Zenodo doi:10.5281/zenodo.20536564)",
  "temperature_source": "",
  "sunlight_note": "",
  "source_notes": "Radiation is real MSL/RAD data (sols 1500-1513 of the mission). Temperature and sunlight fields are still placeholders pending a second real dataset.",
  "days": [
    {
      "date": "SOL 1500",
      "radiation_dose_rate": 0.261,
      "surface_temp_c": null,
      "sunlight_hours": null
    }
  ]
}
```

- `radiation_dose_rate` is in **mGy/day** (absorbed dose), not mSv
  (dose-equivalent) — converting to true mSv needs a radiation-quality-factor
  this dataset doesn't provide, so the UI label reads "mGy" accordingly.
- Any field may be `null`; `DataLoader` carries the last known real value
  forward and marks that day `is_gap_filled: true`, falling back to an
  explicit numeric default if there's no prior value at all (currently the
  case for every sol's `surface_temp_c`/`sunlight_hours`, until the second
  dataset is in).

---

## Data sources

| Variable | Instrument / Mission | Source |
|---|---|---|
| Radiation dose | RAD (Radiation Assessment Detector) / Curiosity, MSL | **Live in-game now.** E-detector dose rate, notch-filtered, sol-averaged from raw sub-daily readings. Heber & Löwe (2026), Zenodo doi:`10.5281/zenodo.20536564`. Sols 1500–1513 used as the current sample window. |
| Surface temperature | MEDA Air Temperature Sensor / Perseverance, Mars 2020 | Planned. Hueso et al. (2024), Zenodo doi:`10.5281/zenodo.11198655`. |
| Pressure (context data) | Multi-mission Mars surface pressure corpus | Planned, Zenodo. |

Because these will come from two rovers at two different craters and
mission timelines once both are in, days are aligned **by sol number**, not
by real Earth calendar date — disclosed on the debrief screen rather than
implied to be one continuous real-time feed.

---

## Supporting docs (not part of the Godot project)

- `SETUP.md` — full build/setup reference.
- `video1-script.md` — 240-second prescreening pitch video script.

---

## Roadmap / open items

- [x] Replace placeholder radiation data with real parsed MSL/RAD values.
- [ ] Replace placeholder temperature/sunlight data with real parsed
      MEDA/pressure values, then merge into one complete `mission_data.json`.
- [ ] Add sprite-sheet animations for the six mascot states (currently
      falls back to emoji).
- [ ] Playtest balance from a deliberately neglected starting state, not
      only from 100% vitals.
- [ ] Expand `AssistantEngine.QUESTIONS` with more preset questions as
      playtesting surfaces what kids actually want to ask Kasei.
- [ ] Consider a second `HistoryChart` for raw environment readings
      alongside the vitals chart — each series would need its own min/max
      normalization since they're on different scales.
- [ ] Style the chat/chart `ScrollContainer`'s scrollbar track fully
      transparent (grabber already styled; track fix pending).
