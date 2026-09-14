#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
guard_check.py - kiem moi RAO CHAN neu trong .claude/IMPORTANT_FIXED_BUGS.md
con ton tai that trong code.

VI SAO: file bay co mot CUA RA - bay nao da co rao chan trong code thi van
xuoi duoc chuyen xuong .claude/archive/. Cua ra do chi an toan neu con dam
bao duoc rang rao chan van con. Xoa mot ham rao chan di ma van xuoi da nam
duoi archive/ la MAT KIEN THUC LANG LE: khong ai thay, va bay quay lai.

CHAY (tu goc repo):    python .claude/guard_check.py
Exit code 1 khi thieu rao chan -> cam duoc vao CI / pre-commit hook.
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# --- CAU HINH: sua 3 dong nay cho dung du an -------------------------------
SOURCE_GLOBS = ["lib/**/*.dart", "tool/**/*.dart", "test/**/*.dart",
                "windows/runner/*.cpp"]           # noi rao chan phai ton tai
# test/ nam trong glob co chu y: nhieu rao chan cua du an nay la test khoa
# bat bien tren file da sinh (trad2simp.tsv, SudachiVariants.txt, manifest).
BUGS    = os.path.join(ROOT, ".claude", "IMPORTANT_FIXED_BUGS.md")
ARCHIVE = os.path.join(ROOT, ".claude", "archive", "FIXED_BUGS_guarded.md")
# ---------------------------------------------------------------------------


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def parse_rows(md):
    """[(so, ten bay, muc, o rao chan)] tu Bang bay (>=4 cot, cot 1 la so)."""
    rows = []
    for ln in md.splitlines():
        if not ln.startswith("|"):
            continue
        cells = [c.strip() for c in ln.strip("|").split("|")]
        if len(cells) < 4 or not cells[0].isdigit():
            continue
        guard = cells[2]
        level = ("OK"   if guard.startswith("\u2705") else
                 "PART" if guard.startswith("\U0001f536") else "NONE")
        rows.append((int(cells[0]), cells[1], level, guard))
    return rows


def guard_names(cell):
    """Tach symbol tu o: `mod.py::fn`, `Cls.method()`, `cfg.rb (remove_const)`, `fn()`.

    THU TU PATTERN QUAN TRONG: dang `(symbol)` phai duoc thu TRUOC dang
    `.method(`, neu khong thi `cfg.rb (remove_const)` bi boc ra "rb" va
    `util.dart (fixKey)` bi boc ra "dart" - ma "dart"/"ts" thi co mat o moi
    file nen check se PASS GIA vinh vien.
    """
    out = []
    for lit in re.findall(r"`([^`]+)`", cell):
        for pat in (r"::(\w+[!?]?)", r"\((\w+[!?]?)\)", r"\.(\w+[!?]?)\s*\(",
                    r"^(\w+[!?]?)\s*\(", r"\.(\w+[!?]?)$"):
            m = re.search(pat, lit)
            if m:
                out.append(m.group(1))
                break
    return out


def main():
    md = read(BUGS)
    if not md:
        sys.exit("Khong doc duoc %s" % BUGS)
    rows = parse_rows(md)
    if not rows:
        sys.exit("Khong tim thay Bang bay trong %s" % BUGS)

    files = []
    for g in SOURCE_GLOBS:
        files += glob.glob(os.path.join(ROOT, g), recursive=True)
    if not files:
        sys.exit("SOURCE_GLOBS khong khop file nao - sua cau hinh dau script.")
    blob = "\n".join(read(p) for p in sorted(set(files)))

    missing = []
    print("KIEM RAO CHAN  (%d bay trong bang, %d file nguon)" % (len(rows), len(files)))
    print("-" * 78)
    for num, name, level, cell in rows:
        if level == "NONE":
            continue
        names = guard_names(cell)
        if not names:
            missing.append((num, name, "(khong tach duoc ten ham tu: %s)" % cell))
            continue
        for fn in names:
            if not re.search(r"\b%s(?!\w)" % re.escape(fn), blob):
                missing.append((num, name, fn))

    for num, name, fn in missing:
        print("  THIEU  bay #%-2d %-46s -> %s" % (num, name[:46], fn))

    n_ok   = sum(1 for r in rows if r[2] == "OK")
    n_part = sum(1 for r in rows if r[2] == "PART")
    n_none = sum(1 for r in rows if r[2] == "NONE")
    n_arch = read(ARCHIVE).count("\n### ")
    print("  [OK]   da co rao chan : %d bay   (archive giu %d muc)" % (n_ok, n_arch))
    print("  [PART] mot phan       : %d bay" % n_part)
    print("  [NONE] chua co        : %d bay  <- co hoi viet rao chan moi" % n_none)
    print("-" * 78)

    if n_ok != n_arch:
        print("LECH: %d bay danh dau OK nhung archive co %d muc." % (n_ok, n_arch))
        print("  -> moi bay ✅ phai co dung mot muc van xuoi trong archive.")
        return 1
    if missing:
        print("HONG: %d rao chan neu trong bang KHONG CO trong code." % len(missing))
        print("  -> hoac viet lai ham do, hoac keo bay tu archive/ ve va ha xuong ❌.")
        return 1
    print("OK: moi rao chan neu trong bang deu con trong code.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
