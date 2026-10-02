CHALLENGE
Build a Junior Astronaut Mission Trainer

Space-themed STEM content often oversimplifies the engineering trade-offs
that define a real mission or presents them at a level too complex to
hold a young learner's attention. Few tools make those trade-offs both
tangible and fun. Your challenge is to design and build an interactive
game or app that lets students run a lunar or Martian outpost, balancing
competing demands like life support, radiation shielding, power, and food
production, so they experience firsthand the decisions that determine
whether a mission fails or succeeds.

MY SOLUTION — a tamagotchi-style Mars outpost survival game (Godot 4.x)

Core idea: instead of a digital pet, the player keeps a Mars outpost
alive, using real NASA environmental data to drive daily threats. A small
creature mascot lives at the outpost and visibly reacts to how it's doing.

Gameplay loop, per SOL (Mars day):
1. Game starts live on SOL 1 — no idle intro screen. Player sees that
   sol's real data (radiation dose, surface temp, sunlight/pressure) and
   four vitals at 100%: Life Support, Power, Radiation Shield, Food
   Production.
2. Player spends two shared resources — Energy and Manpower — on care
   actions (Repair Life Support, Boost Power, Reinforce Shield, Tend
   Food), each costing a different mix of both. Energy is capped by
   current Power; Manpower is capped by current Life Support (with a
   fatigue penalty below a threshold) — so a struggling outpost has LESS
   capacity to recover, which is the actual "competing demands" tension.
3. Pressing "End Day" applies that sol's real data as decay to the
   vitals, then shows a "SOL X CONSEQUENCES" panel: before → after
   numbers for all four vitals, plus an auto-generated plain-language
   cause line (e.g. "Low sunlight reduced power generation. Reduced
   power also affected food production.").
4. On notable data spikes (extreme radiation/cold/darkness), a separate,
   rarer "why" note explains the real scientific phenomenon in
   kid-readable language — this is the educational layer.
5. The mascot's expression is driven by whichever vital is currently
   WORST (not the average) — one neglected system visibly drags the
   whole mascot down, reinforcing the lesson.
6. Mission ends in SUCCESS (survived the full real dataset) or FAILURE
   (any vital hit 0), followed by a debrief screen: final vitals, days
   survived, and the real NASA data source cited by name.

Real data sources used:
- Temperature: Perseverance/MEDA (NASA PDS Atmospheres Node)
- Radiation: Curiosity/RAD (NASA PDS Planetary Plasma Interactions Node)
- Pressure: unified multi-mission Mars pressure corpus (Zenodo)

CURRENT FILE STRUCTURE (Godot project, res://)

res://
├── data/
│   └── mission_data.json          — sol-by-sol real data (radiation_dose_rate, surface_temp_c, sunlight_hours, date), currently placeholder-shaped, being replaced with real parsed values
├── scripts/
│   ├── DataLoader.gd               — Autoload. Loads mission_data.json once, exposes get_day(n) and total_days()
│   ├── StatsManager.gd             — Autoload. Core game logic: 4 vitals, Energy/Manpower resource pools (derived from current Power/Life Support), advance_day() decay + consequences + educational notes, perform_action()/can_afford(), mission success/failure + debrief text generation
│   ├── OutpostUI.gd                — Main scene controller. Wires all UI (bars, buttons, labels) to StatsManager signals. Handles mobile readability: font-size overrides applied in _ready(), bar overlay labels showing "Title XX%" (TextureProgressBar has no built-in text)
│   └── CharacterPortrait.gd        — Mascot controller. AnimatedSprite2D with 6 sprite-sheet states (thriving/stable/strained/critical/failed/success), driven by StatsManager's worst current vital, emoji fallback if an animation is missing
└── scenes/
    └── Outpost.tscn                — Main scene, mobile portrait layout (1080×1920 reference resolution)
        Control (root, OutpostUI.gd)
        ├── Background (TextureRect)
        ├── CharacterPortrait (Control, CharacterPortrait.gd)
        │   ├── ModelHolder (Control) → ModelSprite (AnimatedSprite2D)
        │   └── FaceLabel (Label, emoji fallback)
        ├── VBoxContainer
        │   ├── DayLabel, ConsequencesLabel, MissionLogLabel, NoteLabel (Labels)
        │   ├── LifeSupportRow / PowerRow / RadiationRow / FoodRow (Control, each wrapping a TextureProgressBar + overlay Label)
        │   ├── ResourcesLabel (Label)
        │   ├── Actions (HBoxContainer) → 4 icon+text Buttons
        │   └── EndDayButton (TextureButton)
        └── DebriefPanel (PanelContainer, full-screen overlay)
            └── DebriefVBox → DebriefLabel, RestartButton

Supporting docs (not in the Godot project itself):
- SETUP.md — full build/setup reference: autoload registration, node tree, asset specs, data sources, known gotchas (e.g. TextureProgressBar/TextureButton type mismatches)
- video1-script.md — 240-second prescreening pitch video script

Node names must match script $Path references exactly — a naming mismatch
causes a silent null-instance error at runtime, not an editor warning.