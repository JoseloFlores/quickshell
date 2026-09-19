#!/usr/bin/env python3
"""qs-calendar.py — Thunderbird calendar -> JSON for Quickshell.

Reads the local Thunderbird calendar cache (Google calendars synced by
Thunderbird), expands RRULE recurrences and prints one JSON object:

    {"YYYY-MM-DD": [{"t": title, "s": "HH:MM", "e": "HH:MM", "all": false}, ...], ...}

Usage: qs-calendar.py --from YYYY-MM-DD --to YYYY-MM-DD

Notes:
- Uses the sqlite backup API into a temp copy, so it is safe to run while
  Thunderbird is open (avoids WAL locks).
- All-day detection: starts at 00:00 with >= 23h duration.
- Dates/keys use the event's own wall clock (event timezone or floating).
"""

import argparse
import calendar
import datetime as dt
import glob
import json
import os
import re
import sqlite3
import sys
import tempfile
from zoneinfo import ZoneInfo

WEEKDAYS = {"MO": 0, "TU": 1, "WE": 2, "TH": 3, "FR": 4, "SA": 5, "SU": 6}


def find_tb_cache():
    cands = glob.glob(os.path.expanduser("~/.thunderbird/*/calendar-data/cache.sqlite"))
    best, best_n = None, -1
    for p in cands:
        try:
            db = sqlite3.connect(f"file:{p}?mode=ro", uri=True)
            n = db.execute(
                "SELECT COUNT(*) FROM sqlite_master WHERE name='cal_events'"
            ).fetchone()[0]
            if n:
                m = db.execute("SELECT COUNT(*) FROM cal_events").fetchone()[0]
                if m > best_n:
                    best, best_n = p, m
            db.close()
        except sqlite3.Error:
            continue
    return best


def backup_db(src):
    fd, tmp = tempfile.mkstemp(prefix="qs-cal-", suffix=".sqlite")
    os.close(fd)
    src_db = sqlite3.connect(f"file:{src}?mode=ro", uri=True)
    dst_db = sqlite3.connect(tmp)
    with dst_db:
        src_db.backup(dst_db)
    src_db.close()
    dst_db.close()
    return tmp


def parse_dt(value, tzname):
    """'20220503T200000' or '...Z' -> naive wall datetime in tzname."""
    value = value.strip().rstrip("Z")
    m = re.match(r"(\d{8})T(\d{6})", value)
    if not m:
        m = re.match(r"(\d{8})", value)
        if not m:
            return None
        d = dt.datetime.strptime(m.group(1), "%Y%m%d")
        return d
    d = dt.datetime.strptime(m.group(1) + m.group(2), "%Y%m%d%H%M%S")
    return d


def parse_exdates(ical, tzname):
    out = set()
    for line in ical.splitlines():
        line = line.strip()
        if not line.upper().startswith("EXDATE"):
            continue
        _, _, values = line.partition(":")
        is_utc = any(v.strip().upper().endswith("Z") for v in values.split(","))
        for v in values.split(","):
            v = v.strip()
            if not v:
                continue
            d = parse_dt(v, tzname)
            if d is None:
                continue
            if is_utc and tzname and tzname != "floating":
                d = d.replace(tzinfo=dt.timezone.utc).astimezone(ZoneInfo(tzname)).replace(tzinfo=None)
            out.add(d)
    return out


def parse_rrule(ical):
    rule = {}
    for line in ical.splitlines():
        line = line.strip()
        if not line.upper().startswith("RRULE:"):
            continue
        body = line.split(":", 1)[1]
        for part in body.split(";"):
            if "=" in part:
                k, v = part.split("=", 1)
                rule[k.strip().upper()] = v.strip()
    return rule


def parse_until(value, tzname):
    value = value.strip()
    is_utc = value.upper().endswith("Z")
    d = parse_dt(value, tzname)
    if d is None:
        return None
    if is_utc and tzname and tzname != "floating":
        d = d.replace(tzinfo=dt.timezone.utc).astimezone(ZoneInfo(tzname)).replace(tzinfo=None)
    return d


def add_months(year, month, delta):
    idx = (year * 12 + (month - 1)) + delta
    return idx // 12, idx % 12 + 1


def expand(rule, start_wall, win_from, win_to):
    """Yield naive wall datetimes of occurrences within [win_from, win_to]."""
    freq = rule.get("FREQ", "").upper()
    if freq not in ("DAILY", "WEEKLY", "MONTHLY", "YEARLY"):
        # Unknown frequency: single instance only.
        if win_from <= start_wall <= win_to:
            yield start_wall
        return
    interval = max(1, int(rule.get("INTERVAL", "1")))
    count = rule.get("COUNT")
    count = int(count) if count else None
    until = parse_until(rule["UNTIL"], None) if "UNTIL" in rule else None
    # UNTIL in wall clock of the event is approximated by caller passing tz;
    # here treat naive directly (caller normalizes Z values beforehand is
    # complex, so UNTIL compares on date granularity below).
    emitted = 0

    def accept(occ):
        nonlocal emitted
        if occ < start_wall:
            return None
        if until is not None and occ > until:
            return "stop"
        if occ < win_from or occ > win_to:
            return None
        emitted += 1
        if count is not None and emitted > count:
            return "stop"
        return occ

    if freq == "DAILY":
        k = 0
        while True:
            occ = start_wall + dt.timedelta(days=k * interval)
            if occ > win_to:
                break
            r = accept(occ)
            if r == "stop":
                break
            if r is not None:
                yield r
            k += 1
            if count is not None and emitted >= count:
                break
    elif freq == "WEEKLY":
        byday = rule.get("BYDAY", "")
        days = [WEEKDAYS[d] for d in re.findall(r"[A-Z]{2}", byday.upper()) if d in WEEKDAYS]
        if not days:
            days = [start_wall.weekday()]
        days.sort()
        monday = start_wall - dt.timedelta(days=start_wall.weekday())
        monday = monday.replace(hour=start_wall.hour, minute=start_wall.minute,
                                second=start_wall.second, microsecond=0)
        w = 0
        while True:
            base = monday + dt.timedelta(weeks=w * interval)
            if base > win_to and min(days) >= 0:
                # earliest this week already past window end
                if base + dt.timedelta(days=min(days)) > win_to:
                    break
            stop = False
            for dw in days:
                occ = (base + dt.timedelta(days=dw)).replace(
                    hour=start_wall.hour, minute=start_wall.minute,
                    second=start_wall.second, microsecond=0)
                if occ > win_to and w > 0:
                    # later weeks only get later; but other weekdays same week
                    # may still fit, so just skip this one
                    continue
                r = accept(occ)
                if r == "stop":
                    stop = True
                    break
                if r is not None:
                    yield r
                if count is not None and emitted >= count:
                    stop = True
                    break
            if stop:
                break
            w += 1
            if monday + dt.timedelta(weeks=w * interval) > win_to + dt.timedelta(days=7):
                # Verbraucherschutz: never loop forever
                if count is None:
                    # check termination by window only
                    pass
            if w > 3000:
                break
    elif freq == "MONTHLY":
        bymonthday = rule.get("BYMONTHDAY", "")
        mdays = [int(x) for x in re.findall(r"-?\d+", bymonthday)] or [start_wall.day]
        byday = rule.get("BYDAY", "")
        ord_days = re.findall(r"(-?\d+)?([A-Z]{2})", byday.upper())
        m = 0
        while True:
            y, mo = add_months(start_wall.year, start_wall.month, m * interval)
            month_start = dt.datetime(y, mo, 1)
            if month_start > win_to and m > 0:
                # months only advance; allow one extra for safety
                if month_start.replace(day=1) > win_to + dt.timedelta(days=31):
                    break
            cands = []
            for md in mdays:
                if 1 <= md <= calendar.monthrange(y, mo)[1]:
                    cands.append(dt.datetime(y, mo, md, start_wall.hour,
                                             start_wall.minute, start_wall.second))
            for prefix, wd in ord_days:
                if wd not in WEEKDAYS:
                    continue
                target = WEEKDAYS[wd]
                if prefix:
                    n = int(prefix)
                    if n > 0:
                        first = month_start + dt.timedelta(
                            days=(target - month_start.weekday()) % 7)
                        occ = first + dt.timedelta(weeks=n - 1)
                        if occ.month == mo:
                            cands.append(occ.replace(hour=start_wall.hour,
                                                     minute=start_wall.minute,
                                                     second=start_wall.second))
                    else:
                        last_day = calendar.monthrange(y, mo)[1]
                        last = dt.datetime(y, mo, last_day)
                        first = last - dt.timedelta(days=(last.weekday() - target) % 7)
                        occ = first - dt.timedelta(weeks=abs(n) - 1)
                        if occ.month == mo:
                            cands.append(occ.replace(hour=start_wall.hour,
                                                     minute=start_wall.minute,
                                                     second=start_wall.second))
                else:
                    d = month_start
                    while d.month == mo:
                        if d.weekday() == target:
                            cands.append(d.replace(hour=start_wall.hour,
                                                   minute=start_wall.minute,
                                                   second=start_wall.second))
                        d += dt.timedelta(days=1)
            stop = False
            for occ in sorted(set(cands)):
                if occ > win_to and m > 0:
                    continue
                r = accept(occ)
                if r == "stop":
                    stop = True
                    break
                if r is not None:
                    yield r
                if count is not None and emitted >= count:
                    stop = True
                    break
            if stop:
                break
            m += 1
            if m > 2400:
                break
    elif freq == "YEARLY":
        bymonth = rule.get("BYMONTH", "")
        months = [int(x) for x in re.findall(r"\d+", bymonth)] or [start_wall.month]
        bymonthday = rule.get("BYMONTHDAY", "")
        mdays = [int(x) for x in re.findall(r"-?\d+", bymonthday)] or [start_wall.day]
        y = start_wall.year
        while True:
            if dt.datetime(y, 1, 1) > win_to and y > start_wall.year:
                if dt.datetime(y, 1, 1) > win_to + dt.timedelta(days=366):
                    break
            stop = False
            for mo in sorted(set(months)):
                if not 1 <= mo <= 12:
                    continue
                for md in mdays:
                    if 1 <= md <= calendar.monthrange(y, mo)[1]:
                        occ = dt.datetime(y, mo, md, start_wall.hour,
                                          start_wall.minute, start_wall.second)
                        if occ > win_to and y > start_wall.year:
                            continue
                        r = accept(occ)
                        if r == "stop":
                            stop = True
                            break
                        if r is not None:
                            yield r
                        if count is not None and emitted >= count:
                            stop = True
                            break
                    if stop:
                        break
                if stop:
                    break
            if stop:
                break
            y += interval
            if y - start_wall.year > 200:
                break


def wall_of(start_us, tzname):
    if tzname and tzname != "floating":
        try:
            z = ZoneInfo(tzname)
        except Exception:
            z = dt.timezone.utc
        return dt.datetime.fromtimestamp(start_us / 1e6, tz=z).replace(tzinfo=None), str(tzname)
    return dt.datetime.fromtimestamp(start_us / 1e6, dt.timezone.utc).replace(tzinfo=None), "floating"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="from_", required=True)
    ap.add_argument("--to", dest="to_", required=True)
    args = ap.parse_args()
    win_from = dt.datetime.strptime(args.from_, "%Y-%m-%d")
    win_to = dt.datetime.strptime(args.to_, "%Y-%m-%d") + dt.timedelta(hours=23, minutes=59)

    src = find_tb_cache()
    if not src:
        print(json.dumps({}))
        print("qs-calendar: no Thunderbird calendar cache found", file=sys.stderr)
        return 0
    tmp = backup_db(src)
    try:
        db = sqlite3.connect(tmp)
        db.row_factory = sqlite3.Row
        masters = db.execute(
            "SELECT id, title, event_start, event_end, event_start_tz, ical_status"
            " FROM cal_events WHERE recurrence_id IS NULL"
        ).fetchall()
        overrides = {}
        for r in db.execute(
            "SELECT id, title, event_start, event_end, event_start_tz, ical_status,"
            " recurrence_id FROM cal_events WHERE recurrence_id IS NOT NULL"
        ):
            overrides[(r["id"], int(r["recurrence_id"]))] = r
        recur = {}
        for r in db.execute("SELECT item_id, icalString FROM cal_recurrence"):
            recur.setdefault(r["item_id"], []).append(r["icalString"])
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass

    out = {}

    def add(wall, title, dur_h, allday):
        if not (win_from <= wall <= win_to):
            return
        key = wall.strftime("%Y-%m-%d")
        end = wall + dt.timedelta(hours=dur_h)
        entry = {"t": title or "(sin título)",
                 "s": "Todo el día" if allday else wall.strftime("%H:%M"),
                 "e": "" if allday else end.strftime("%H:%M"),
                 "all": allday}
        day = out.setdefault(key, [])
        if (entry["t"], entry["s"]) not in [(e["t"], e["s"]) for e in day]:
            day.append(entry)

    for m in masters:
        status = (m["ical_status"] or "").upper()
        if status == "CANCELLED":
            continue
        wall, tzname = wall_of(m["event_start"], m["event_start_tz"])
        dur_h = max(0.0, (m["event_end"] - m["event_start"]) / 3.6e9)
        allday = wall.hour == 0 and wall.minute == 0 and dur_h >= 23.0
        rules = [r for r in recur.get(m["id"], []) if "RRULE" in r.upper()]
        exdates = set()
        for blob in recur.get(m["id"], []):
            exdates |= parse_exdates(blob, tzname if tzname != "floating" else None)
        if not rules:
            add(wall, m["title"], dur_h, allday)
            continue
        for blob in [b for b in recur.get(m["id"], []) if "RRULE" in b.upper()]:
            rule = parse_rrule(blob)
            # Normalize UNTIL with event tz for wall-clock compare
            if "UNTIL" in rule:
                u = rule["UNTIL"].strip()
                if u.upper().endswith("Z") and tzname != "floating":
                    z = ZoneInfo(tzname)
                    uu = dt.datetime.strptime(u[:-1], "%Y%m%dT%H%M%S").replace(
                        tzinfo=dt.timezone.utc).astimezone(z).replace(tzinfo=None)
                    rule = dict(rule)
                    rule["UNTIL"] = uu.strftime("%Y%m%dT%H%M%S")
            for occ in expand(rule, wall, win_from, win_to):
                if occ in exdates:
                    continue
                # recurrence override?
                key_us = None
                if tzname != "floating":
                    z = ZoneInfo(tzname)
                    key_us = int(occ.replace(tzinfo=z).astimezone(
                        dt.timezone.utc).timestamp() * 1e6)
                else:
                    key_us = int(occ.replace(tzinfo=dt.timezone.utc).timestamp() * 1e6)
                ov = overrides.pop((m["id"], key_us), None)
                if ov is not None:
                    if (ov["ical_status"] or "").upper() == "CANCELLED":
                        continue
                    ow, _ = wall_of(ov["event_start"], ov["event_start_tz"])
                    od = max(0.0, (ov["event_end"] - ov["event_start"]) / 3.6e9)
                    oa = ow.hour == 0 and ow.minute == 0 and od >= 23.0
                    add(ow, ov["title"], od, oa)
                else:
                    add(occ, m["title"], dur_h, allday)

    for v in out.values():
        v.sort(key=lambda e: (e["all"], e["s"]))
    print(json.dumps(out, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
