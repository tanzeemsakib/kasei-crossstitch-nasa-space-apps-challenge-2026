# Kasei: Mars Outpost Trainer

**Team CrossStitch** · NASA Space Apps Challenge 2026 · *Build a Junior Astronaut Mission Trainer*

- **Tanzeem Ahmed**: team lead, game design and code
- **Fatima Mahzabin**: art director, character and UI art

**Play it in the browser (no download, no account):**
https://tanzeemsakib.github.io/kasei-crossstitch-nasa-space-apps-challenge-2026/ · also on itch.io: https://tanzeem-ahmed-sakib.itch.io/kasei

> A student entry for the NASA Space Apps Challenge. Not an official NASA product.

---

## The challenge

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

A **tamagotchi-style Mars outpost survival game** for kids aged 7 to 12,
built in **Godot 4**. Instead of a digital pet, the player keeps a whole
outpost alive. A small robot mascot, **Kasei**, lives at the outpost and
visibly reacts to how it's doing. One neglected system drags the whole
outpost (and Kasei's mood) down, which is the core lesson: real missions
live and die on competing trade-offs, not on any single system.

The daily conditions are **real measurements from NASA's Curiosity rover** at
Gale Crater, not invented numbers. The data is **archived, not live**, and
the game says so on screen.

---

## How to play

Each **sol** (a Martian day, about 24 h 40 min) is one turn.

1. Four systems start at 100%: **Life Support, Power, Radiation Shield,
   Food Production**. The telemetry panel shows that sol's real conditions.
2. You have two shared resources, **Energy** and **Manpower**. Four care
   actions (repair Life Support, boost Power, reinforce the Shield, tend
   Food) each cost a different mix of the two. You can't do everything.
   - Energy is capped by current Power.
   - Manpower is capped by current Life Support (with a fatigue penalty
     below a threshold).
   - Both keep a small minimum so a struggling outpost isn't completely
     stuck, but it has less capacity to recover.
3. Press **End Day**. That sol's real data is applied to the outpost: more
   radiation wears the shield faster, colder nights strain Life Support, and
   so on. A plain-language cause line explains what happened, a rarer
   "educational note" explains the science behind unusual readings, and a
   one-line forecast previews the next sol.
4. Kasei's expression follows your **weakest** system, not the average.
5. The mission ends in **success** (you survive the whole data window) or
   **failure** (a system hits 0%), followed by a debrief screen.

**Tools for the player**

| Tool | What it does |
|---|---|
| **Ask Kasei** (chat icon) | Preset questions, e.g. "What's a sol?", "What's a radiation dose?", "Why is my shield low?", "Where does this data come from?". Answers come from the real data and the current game state. It is deliberately **not** a free-text or LLM chatbot, so every answer is deterministic and traceable. |
| **History chart** (chart icon) | The four vitals plotted sol by sol, in one colour using four line styles. |
| **Undo** | Takes back your last action within the current sol, refunding its cost. |
| **Info** | A popup with each action's Energy and Manpower cost and a note about the data. |

---

## Real NASA data

All conditions come from **Curiosity (Mars Science Laboratory) at Gale
Crater, sols 1500 to 1513 (24 October to 7 November 2016)**. The data is
archived. The game never presents it as live.

| In the game | Instrument | Source |
|---|---|---|
| **Radiation dose** (mGy per day) | **RAD**, Radiation Assessment Detector | E-detector dose rate, notch-filtered, averaged per sol. Heber & Löwe (2026), Zenodo, doi:[10.5281/zenodo.20536564](https://doi.org/10.5281/zenodo.20536564) |
| **Surface temperature** (night low and daytime high) | **REMS**, Rover Environmental Monitoring Station | Calibrated MODRDR data (ambient air temperature), NASA PDS Atmospheres Node |
| **Air pressure** (pascals) | **REMS** | Calibrated MODRDR data, mean per sol |
| **Sunlight** (hours) | **REMS** | Calibrated ADR data (solar zenith angle). Hours the Sun is above the rover's horizon |

The REMS data comes from the NASA Planetary Data System's Atmospheres Node
(`mslrem_1001` collection, calibrated data).

### How the raw data became `mission_data.json`

Everything is reproducible from the scripts in [`tools/`](tools/):

- `tools/process_rad.py`: reads the RAD file and takes the mean notch-filtered
  dose per sol (micro Gray per day divided by 1000 gives mGy per day).
- `tools/download_rems.ps1`: downloads the 28 REMS files used (RMD and ADR for
  each sol) from the PDS archive.
- `tools/rems_daily_summary.py`: reads those files and writes one row per
  sol:
  - **Temperature:** the `AMBIENT_TEMP` column, dropping missing values and
    readings the instrument flags as unreliable or outside its operating
    range. The game uses each sol's lowest value (night low) and highest
    (daytime high).
  - **Pressure:** the `PRESSURE` column, mean per sol.
  - **Sunlight:** from the `SOLAR_ZENITHAL_ANGLE` column. Sunrise and sunset
    are where the angle crosses 90 degrees, interpolated across gaps in the
    recording.

### What is real, and what is game

- **Real:** radiation, surface temperature, pressure, sunlight.
- **Game state built on top of the data:** the four vitals, Energy, Manpower,
  and the telemetry readouts for interior temperature, oxygen, CO2, water
  and food reserve (derived from the vitals, by design).

### Caveats we want to be upfront about

- Our processing (night low and day high, filtering, interpolation) is ours.
  The raw measurements are NASA's.
- Sunlight is measured from the rover's own frame, so tilt on slopes shifts
  sunrise and sunset by a few minutes. Daylight varies a little more from
  sol to sol than the real Sun does.
- Radiation is in **mGy per day** (absorbed dose), not mSv, because
  converting to dose equivalent needs a quality factor the dataset doesn't
  provide.
- The window of 14 sols is a sample, not the whole mission.

---

## Visual design

Built from a Figma mockup as a portrait layout, using a deliberately small
palette:

| Role | Hex |
|---|---|
| Background | `#F8E9E9` |
| Fill (buttons, bars) | `#A070A1` |
| Text and borders | `#724060` |

Telemetry text uses **Space Mono** for a technical readout feel. The
history-chart lines are told apart by **line style** (solid, dashed, dotted,
dash-dot), not colour. Kasei has six states (thriving, stable, strained,
critical, failed, success), each a **two-frame animation**, with a head crop
of the same art shown in the small portrait box. The overlays (chat, chart,
end screen) share one panel style.

The project uses **Stretch Mode `canvas_items`, Aspect `keep`**, so the
layout scales as one unit to any screen.

---

## Project structure

```
project.godot
data/mission_data.json        # per-sol real data + sources + archive note
script/
  DataLoader.gd               # autoload: loads the data, get_day(n)
  StatsManager.gd             # autoload: game logic
  OutpostUI.gd                # main scene controller
  CharacterPortrait.gd        # Kasei's expression and portrait crop
  AssistantEngine.gd          # "Ask Kasei" preset Q&A
  HistoryChart.gd             # dependency-free line chart (_draw)
scenes/Outpost.tscn           # main scene
tools/                        # data processing (see above)
docs/                         # web export (index.html and friends)
```

| Script | Role |
|---|---|
| `DataLoader.gd` | Loads `mission_data.json` once. Fills any missing field from the last known value and flags it. Returns `{}` past the last sol, which signals mission complete, so it must not clamp. |
| `StatsManager.gd` | The four vitals, Energy and Manpower, daily decay, cause lines, educational notes, the forecast, Undo, history, and the debrief. |
| `OutpostUI.gd` | Connects every UI element to `StatsManager`. Finds nodes by unique name, with startup asserts that name any missing node. Derives the flavour readouts from the vitals. |
| `CharacterPortrait.gd` | Picks Kasei's animation from the worst vital and crops the portrait. |
| `AssistantEngine.gd` | Fixed question set answered from live data and state. |
| `HistoryChart.gd` | Draws the line chart from normalised series. |

### Run it locally

1. Install **Godot 4** and open `project.godot`.
2. Check *Project Settings → Autoload*: `DataLoader` and `StatsManager`.
3. Run the main scene.

### Export for the web

1. *Project → Export → Add → Web.* **Turn Thread Support off** (plain
   GitHub Pages can't send the headers a threaded build needs).
2. Export to `docs/index.html`.
3. In GitHub: *Settings → Pages → Deploy from a branch → `main` and `/docs`*.
4. For itch.io, zip the contents of `docs/` (with `index.html` at the top
   level of the zip) and upload it as an HTML5 game.

---

## Known limitations and next steps

- **One fixed sample window.** Every game replays sols 1500 to 1513. The RAD
  data covers 2,800 or so sols, including real solar-particle-event spikes;
  using those as extra scenarios would add replayability and link shielding
  decisions to space weather.
- **Power rarely drops in this window.** Daylight is steady at about 12
  hours, so Power stays healthy. Making Power respond more strongly to
  sunlight, or to a dust-storm window, would strengthen the trade-off.
- **Communication delay isn't modelled yet.**
- The Emergency Protocol exists in `StatsManager.gd` but has no button in the
  shipped scene.
- The telemetry panel is dense; a simple-view toggle would help younger
  players.

---

## Credits

- **Radiation data:** Heber & Löwe (2026), Zenodo, doi:10.5281/zenodo.20536564
  (MSL/RAD).
- **Weather data:** MSL/REMS, NASA Planetary Data System, Atmospheres Node.
- **Font:** Space Mono (Google Fonts, SIL Open Font License).
- **Game, code and art:** Team CrossStitch.
