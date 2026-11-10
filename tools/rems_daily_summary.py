#!/usr/bin/env python3
"""
Summarise Curiosity REMS MODRDR (RMD) and ADR sol files into ONE small CSV.

Usage:
    python rems_daily_summary.py [folder or files ...]

With no argument it looks in the current folder. It finds every *RMD*.TAB and
*ADR*.TAB file, reads the fixed-width columns using the byte positions from the
PDS labels, and writes rems_daily_summary.csv (in the folder you ran it from),
one row per sol:

    sol, rows_total, temp_rows_used, temp_min_c, temp_max_c, temp_mean_c,
    pressure_rows_used, pressure_mean_pa, uv_peak_wm2,
    daylight_hours, sunrise_gap_min, sunset_gap_min

Method notes
  * Air temperature = AMBIENT_TEMP (estimated ambient air temperature, K) in C.
    The rover samples more often by day than at night, so temp_mean_c is the
    mean of the hourly means (every hour weighted equally), not a plain mean.
    Rows are dropped when the value is missing (-999) or out of a sane range,
    or when the confidence string marks the reading unreliable / out of the
    sensor's operating range.
  * Pressure = PRESSURE in pascals.
  * uv_peak_wm2 = the highest UV_ABC irradiance recorded that sol (a proxy for
    how clear the sky was; dusty sols read lower).
  * daylight_hours (Earth hours) comes from the ADR solar zenith angle: the
    time between the Sun rising above and setting below the rover's horizontal
    plane (zenith < 90 degrees). The rover does not record all day, so each
    crossing is interpolated between the last reading before it and the first
    after it. sunrise_gap_min / sunset_gap_min say how wide the gap in the data
    was at each crossing: small = trustworthy, large = estimate.
"""
import csv
import glob
import os
import sys
from collections import defaultdict

# 1-based byte start and length, straight from the .xml labels.
LMST = (13, 18)
AMBIENT_TEMP = (158, 7)
AMBIENT_CONF = (167, 12)   # 9 flags, right-aligned; byte 7 = in range, byte 8 = reliable
UV_ABC = (205, 7)
PRESSURE = (345, 7)
PS_CONF = (362, 8)         # 2 flags, right-aligned; byte 1 = shadow effect (0 = present)

# ADR (ancillary) file: used only for daylight.
ADR_TIMESTAMP = (1, 10)    # seconds since noon 1-Jan-2000
ADR_ZENITH = (58, 7)       # SOLAR_ZENITHAL_ANGLE, degrees from the rover's +Z (up)

MAX_INTERP_GAP_S = 4 * 3600  # don't interpolate across a data gap longer than this


def field(line, spec):
    start, length = spec
    return line[start - 1:start - 1 + length]


def to_float(text):
    try:
        return float(text)
    except ValueError:
        return None


def sol_of(lmst):
    # LMST format: SSSSSMHH:MM:SS.sss  (sol, separator, time)
    digits = lmst[:5].strip()
    return int(digits) if digits.isdigit() else None


def hour_of(lmst):
    try:
        return int(lmst[6:8])
    except ValueError:
        return None


def conf_ok(conf, index):
    """True unless the confidence string explicitly marks flag `index` bad.

    The strings are right-aligned with leading spaces (e.g. '   011XX1111'),
    so the padding is stripped first and `index` counts from the first real
    flag, matching 'Byte 0, Byte 1, ...' in the PDS label. 'X' = unknown = OK."""
    flags = conf.strip()
    return len(flags) <= index or flags[index] != "0"


def collect(paths):
    temps = defaultdict(list)        # (hour, value_c), confidence-filtered
    temps_loose = defaultdict(list)  # range check only
    press = defaultdict(list)
    uv_peak = {}
    total = defaultdict(int)

    for path in paths:
        with open(path, "r", encoding="ascii", errors="replace") as handle:
            for raw in handle:
                line = raw.rstrip("\r\n")
                if len(line) < 360:
                    continue
                sol = sol_of(field(line, LMST))
                if sol is None:
                    continue
                total[sol] += 1
                hour = hour_of(field(line, LMST))

                t_k = to_float(field(line, AMBIENT_TEMP))
                if t_k is not None and 100.0 < t_k < 350.0 and hour is not None:
                    t_c = t_k - 273.15
                    temps_loose[sol].append((hour, t_c))
                    # Byte 8 = observation reliable; byte 7 = error inside the
                    # sensor's operational range (< 5 K).
                    ambient_conf = field(line, AMBIENT_CONF)
                    if conf_ok(ambient_conf, 8) and conf_ok(ambient_conf, 7):
                        temps[sol].append((hour, t_c))

                p = to_float(field(line, PRESSURE))
                if p is not None and 100.0 < p < 1500.0:
                    if conf_ok(field(line, PS_CONF), 1):
                        press[sol].append(p)

                uv = to_float(field(line, UV_ABC))
                if uv is not None and 0.0 <= uv < 200.0:
                    if sol not in uv_peak or uv > uv_peak[sol]:
                        uv_peak[sol] = uv
    return total, temps, temps_loose, press, uv_peak


def collect_daylight(paths):
    """Per sol: interpolated sunrise and sunset times (seconds) where the solar
    zenith angle crosses 90 degrees, plus the width of the data gap at each.

    Rows come in time order. A crossing is found between two consecutive rows
    of the same sol; linear interpolation between them gives the crossing time.
    If the data starts or ends in daylight (no row on the night side to
    interpolate from), the first/last daytime row is used instead, with a gap
    of None."""
    out = {}
    for path in paths:
        prev = None  # (sol, ts, zenith)
        with open(path, "r", encoding="ascii", errors="replace") as handle:
            for raw in handle:
                line = raw.rstrip("\r\n")
                if len(line) < 64:
                    continue
                zenith = to_float(field(line, ADR_ZENITH))
                if zenith is None or not (0.0 <= zenith <= 180.0):
                    continue
                stamp = to_float(field(line, ADR_TIMESTAMP))
                sol = sol_of(field(line, LMST))
                if stamp is None or sol is None:
                    continue
                rec = out.setdefault(sol, {"rise": None, "rise_gap": None,
                                           "set": None, "set_gap": None,
                                           "first_day": None, "last_day": None})
                if zenith < 90.0:
                    if rec["first_day"] is None or stamp < rec["first_day"]:
                        rec["first_day"] = stamp
                    if rec["last_day"] is None or stamp > rec["last_day"]:
                        rec["last_day"] = stamp

                if prev is not None and prev[0] == sol and 0 < stamp - prev[1] <= MAX_INTERP_GAP_S:
                    p_sol, p_ts, p_z = prev
                    if p_z >= 90.0 and zenith < 90.0 and rec["rise"] is None:
                        frac = (p_z - 90.0) / (p_z - zenith)
                        rec["rise"] = p_ts + frac * (stamp - p_ts)
                        rec["rise_gap"] = stamp - p_ts
                    elif p_z < 90.0 and zenith >= 90.0:
                        frac = (90.0 - p_z) / (zenith - p_z)
                        rec["set"] = p_ts + frac * (stamp - p_ts)   # keep the last one
                        rec["set_gap"] = stamp - p_ts
                prev = (sol, stamp, zenith)

    result = {}
    for sol, rec in out.items():
        rise = rec["rise"] if rec["rise"] is not None else rec["first_day"]
        sset = rec["set"] if rec["set"] is not None else rec["last_day"]
        if rise is None or sset is None:
            continue
        result[sol] = {
            "hours": (sset - rise) / 3600.0,
            "rise_gap_min": None if rec["rise_gap"] is None else rec["rise_gap"] / 60.0,
            "set_gap_min": None if rec["set_gap"] is None else rec["set_gap"] / 60.0,
        }
    return result


def hourly_mean(samples):
    by_hour = defaultdict(list)
    for hour, value in samples:
        by_hour[hour].append(value)
    means = [sum(v) / len(v) for v in by_hour.values()]
    return sum(means) / len(means)


def main(argv):
    targets = argv[1:] or ["."]
    paths = []
    adr_paths = []
    for target in targets:
        if os.path.isdir(target):
            for pattern in ("*RMD*.TAB", "*RMD*.tab"):
                paths += glob.glob(os.path.join(target, pattern))
            for pattern in ("*ADR*.TAB", "*ADR*.tab"):
                adr_paths += glob.glob(os.path.join(target, pattern))
        elif "ADR" in os.path.basename(target).upper():
            adr_paths.append(target)
        else:
            paths.append(target)
    paths = sorted(set(paths))
    adr_paths = sorted(set(adr_paths))
    if not paths:
        print("No *RMD*.TAB files found. Run this in the folder that holds them.")
        return 1
    if not adr_paths:
        print("Note: no *ADR*.TAB files found, so daylight hours will be blank.")

    total, temps, temps_loose, press, uv_peak = collect(paths)
    daylight = collect_daylight(adr_paths) if adr_paths else {}

    def r(value, digits):
        return None if value is None else round(value, digits)

    rows = []
    for sol in sorted(total):
        used = temps[sol]
        note = ""
        if not used and temps_loose[sol]:
            used = temps_loose[sol]
            note = "  (confidence filter dropped everything; used range check only)"
        if used:
            values = [v for _, v in used]
            t_min, t_max, t_mean = min(values), max(values), hourly_mean(used)
        else:
            t_min = t_max = t_mean = None
        p_vals = press[sol]
        p_mean = sum(p_vals) / len(p_vals) if p_vals else None
        day = daylight.get(sol)
        rows.append([
            sol, total[sol], len(used),
            r(t_min, 1), r(t_max, 1), r(t_mean, 1),
            len(p_vals), r(p_mean, 1),
            r(uv_peak.get(sol), 2),
            r(day["hours"], 2) if day else None,
            r(day["rise_gap_min"], 0) if day else None,
            r(day["set_gap_min"], 0) if day else None,
        ])
        row = rows[-1]
        print("sol %d: %d rows | temp rows %d | min %s max %s mean %s C | pressure %s Pa | UV peak %s | daylight %s h (gap at sunrise %s min, sunset %s min)%s" % (
            sol, total[sol], len(used), row[3], row[4], row[5], row[7], row[8],
            row[9], row[10], row[11], note))

    out = "rems_daily_summary.csv"
    with open(out, "w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["sol", "rows_total", "temp_rows_used", "temp_min_c",
                         "temp_max_c", "temp_mean_c", "pressure_rows_used",
                         "pressure_mean_pa", "uv_peak_wm2", "daylight_hours",
                         "sunrise_gap_min", "sunset_gap_min"])
        writer.writerows(rows)
    print("\nWrote %s (%d sols)" % (out, len(rows)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
