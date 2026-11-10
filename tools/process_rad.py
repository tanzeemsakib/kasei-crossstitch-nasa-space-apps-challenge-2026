#!/usr/bin/env python3
"""
Turn the Curiosity RAD E-detector file into the per-sol radiation values used
in data/mission_data.json.

Source: Heber & Lowe (2026), Zenodo, doi:10.5281/zenodo.20536564
        (file: doseE_sol_filter_update.txt)

Usage:
    python process_rad.py doseE_sol_filter_update.txt [first_sol] [last_sol]

Defaults to sols 1500 to 1513. Prints one line per sol and a JSON snippet.

How the file is laid out (tab-separated, header row first). The header has
fewer names than the file has columns, so columns are read by position:
    0  Datetime (UTC)
    1  year
    2  day of year
    3  sol number (e.g. 1500.0)
    4  DoseE, micro Gray per day
    5  DoseE_filtered, micro Gray per day   <- used here (notch-filtered)

Method: for each sol, take the mean of the filtered dose-rate readings that
fall in that sol, and convert micro Gray per day to milli Gray per day
(divide by 1000). Unit: mGy/day (absorbed dose, not dose equivalent).
"""
import csv
import json
import statistics
import sys
from collections import defaultdict


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    path = argv[1]
    first = int(argv[2]) if len(argv) > 2 else 1500
    last = int(argv[3]) if len(argv) > 3 else 1513

    by_sol = defaultdict(list)
    with open(path, encoding="utf-8") as handle:
        reader = csv.reader(handle, delimiter="\t")
        next(reader)  # header
        for row in reader:
            if len(row) < 6:
                continue
            try:
                sol = int(float(row[3]))
                dose_ugy = float(row[5])
            except ValueError:
                continue
            if first <= sol <= last:
                by_sol[sol].append(dose_ugy)

    result = {}
    for sol in range(first, last + 1):
        values = by_sol.get(sol)
        if not values:
            print("sol %d: no readings" % sol)
            continue
        mgy = statistics.fmean(values) / 1000.0
        result[sol] = round(mgy, 3)
        print("sol %d: %d readings, mean filtered dose %.3f mGy/day" % (sol, len(values), mgy))

    print()
    print(json.dumps({"radiation_dose_rate_by_sol": result}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
