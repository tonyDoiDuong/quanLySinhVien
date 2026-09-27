#!/usr/bin/env python3
"""Aggregate NTA Daily Liquidity Story CSV exports.

Each chart running the indicator writes one CSV per symbol/timeframe
(NTA_DLS_<SYMBOL>_<TF>.csv, one row per finalized story day). This
script merges any number of them and prints the sequence statistics
A-L from the spec, grouped by symbol + timeframe, so M1 / M5 / M15
results can be compared side by side.

Nothing here assumes the ICT/SMC sequence has an edge: it only counts.

Usage:
    python3 tools/dls_stats.py NTA_DLS_XAUUSD_M1.csv NTA_DLS_XAUUSD_M5.csv ...
    python3 tools/dls_stats.py --by-class files...     # split by Asia range class
    python3 tools/dls_stats.py --csv out.csv files...  # also write a summary CSV
"""
from __future__ import annotations

import argparse
import csv
import sys
from collections import OrderedDict
from dataclasses import dataclass, field
from statistics import mean, median


def _b(row: dict, key: str) -> bool:
    return row.get(key, "0").strip() == "1"


def _f(row: dict, key: str) -> float | None:
    v = row.get(key, "").strip()
    if not v:
        return None
    try:
        return float(v)
    except ValueError:
        return None


@dataclass
class Group:
    days: int = 0
    lon_swept_high: int = 0
    lon_swept_low: int = 0
    lon_swept_both: int = 0
    lon_broke_high: int = 0
    lon_broke_low: int = 0
    lon_one_side: int = 0
    ny_opposite: int = 0
    ny_sweep: int = 0
    disp: int = 0
    mss: int = 0
    fvg: int = 0
    retrace: int = 0
    invalid: int = 0
    model: int = 0
    fvg_sb: int = 0
    fvg_out: int = 0
    rt_sb: int = 0
    rt_out: int = 0
    mfe_sb: list = field(default_factory=list)
    mae_sb: list = field(default_factory=list)
    mfe_out: list = field(default_factory=list)
    mae_out: list = field(default_factory=list)

    def add(self, r: dict) -> None:
        self.days += 1
        ls = r.get("london_story", "")
        hi_by = r.get("asia_high_by", "") == "LONDON"
        lo_by = r.get("asia_low_by", "") == "LONDON"
        if ls == "LONDON_SWEPT_ASIA_HIGH" or (ls == "LONDON_SWEPT_BOTH" and hi_by):
            self.lon_swept_high += 1
        if ls == "LONDON_SWEPT_ASIA_LOW" or (ls == "LONDON_SWEPT_BOTH" and lo_by):
            self.lon_swept_low += 1
        if ls == "LONDON_SWEPT_BOTH":
            self.lon_swept_both += 1
        if ls == "LONDON_BROKE_ASIA_HIGH":
            self.lon_broke_high += 1
        if ls == "LONDON_BROKE_ASIA_LOW":
            self.lon_broke_low += 1
        if ls in ("LONDON_SWEPT_ASIA_HIGH", "LONDON_SWEPT_ASIA_LOW"):
            self.lon_one_side += 1
            if _b(r, "ny_opposite_london_swept"):
                self.ny_opposite += 1
        self.ny_sweep += _b(r, "ny_sweep")
        self.disp += _b(r, "displacement")
        self.mss += _b(r, "mss")
        self.fvg += _b(r, "story_fvg")
        self.retrace += _b(r, "retrace")
        self.invalid += _b(r, "invalidated")
        self.model += _b(r, "model_match")
        if _b(r, "story_fvg"):
            sb = _b(r, "sb_fvg") or _b(r, "sb_mss")
            if sb:
                self.fvg_sb += 1
                self.rt_sb += _b(r, "retrace")
            else:
                self.fvg_out += 1
                self.rt_out += _b(r, "retrace")
            if _b(r, "retrace"):
                mfe, mae = _f(r, "mfe_atr"), _f(r, "mae_atr")
                if mfe is not None and mae is not None:
                    (self.mfe_sb if sb else self.mfe_out).append(mfe)
                    (self.mae_sb if sb else self.mae_out).append(mae)


def pct(n: int, d: int) -> str:
    return f"{n}/{d} ({100.0 * n / d:.0f}%)" if d else f"{n}/0 (-)"


def dist(xs: list) -> str:
    if not xs:
        return "-"
    return f"avg {mean(xs):.2f} | med {median(xs):.2f} | n={len(xs)}"


def rows_for(g: Group) -> "OrderedDict[str, str]":
    o: "OrderedDict[str, str]" = OrderedDict()
    o["days"] = str(g.days)
    o["A London swept Asia High"] = pct(g.lon_swept_high, g.days)
    o["B London swept Asia Low"] = pct(g.lon_swept_low, g.days)
    o["C London swept both sides"] = pct(g.lon_swept_both, g.days)
    o["  London broke Asia High / Low"] = f"{g.lon_broke_high} / {g.lon_broke_low}"
    o["D NY swept opposite London liquidity"] = pct(g.ny_opposite, g.lon_one_side)
    o["E NY sweep -> displacement"] = pct(g.disp, g.ny_sweep)
    o["F displacement -> MSS"] = pct(g.mss, g.disp)
    o["G MSS -> story FVG"] = pct(g.fvg, g.mss)
    o["H story FVG -> retrace"] = pct(g.retrace, g.fvg)
    o["  invalidated after MSS"] = pct(g.invalid, g.mss)
    o["  model 1 / model 2 sequences"] = str(g.model)
    o["I MFE (ATR) in SB"] = dist(g.mfe_sb)
    o["I MFE (ATR) outside SB"] = dist(g.mfe_out)
    o["J MAE (ATR) in SB"] = dist(g.mae_sb)
    o["J MAE (ATR) outside SB"] = dist(g.mae_out)
    o["L FVG -> retrace in SB"] = pct(g.rt_sb, g.fvg_sb)
    o["L FVG -> retrace outside SB"] = pct(g.rt_out, g.fvg_out)
    return o


def read_rows(paths: list[str]) -> list[dict]:
    rows: list[dict] = []
    for p in paths:
        with open(p, newline="", encoding="utf-8-sig") as fh:
            for r in csv.DictReader(fh):
                rows.append({k.strip(): (v or "").strip() for k, v in r.items() if k})
    return rows


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+", help="NTA_DLS_*.csv files")
    ap.add_argument("--by-class", action="store_true", help="also split by Asia range class")
    ap.add_argument("--csv", help="write the summary table to this CSV file")
    a = ap.parse_args(argv)

    rows = read_rows(a.files)
    if not rows:
        print("no rows")
        return 1

    groups: "OrderedDict[str, Group]" = OrderedDict()
    for r in sorted(rows, key=lambda x: (x.get("symbol", ""), x.get("timeframe", ""), x.get("date", ""))):
        keys = [f"{r.get('symbol', '?')} {r.get('timeframe', '?')}"]
        if a.by_class:
            keys.append(f"{keys[0]} asia={r.get('asia_class', '?')}")
        for k in keys:
            groups.setdefault(k, Group()).add(r)

    tables = OrderedDict((k, rows_for(g)) for k, g in groups.items())
    width = max(len(m) for t in tables.values() for m in t)
    for name, t in tables.items():
        print(f"\n=== {name} ===")
        for m, v in t.items():
            print(f"{m.ljust(width)}  {v}")

    if a.csv:
        metrics = list(next(iter(tables.values())).keys())
        with open(a.csv, "w", newline="", encoding="utf-8") as fh:
            w = csv.writer(fh)
            w.writerow(["metric", *tables.keys()])
            for m in metrics:
                w.writerow([m.strip(), *(t[m] for t in tables.values())])
        print(f"\nsummary written to {a.csv}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
