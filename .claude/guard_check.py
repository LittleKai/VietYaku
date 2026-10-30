#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
guard_check.py - kiem moi RAO CHAN neu trong .claude/IMPORTANT_FIXED_BUGS.md
con ton tai that trong code.

VI SAO: file bay co mot CUA RA - bay nao da co rao chan trong code thi van
xuoi duoc chuyen xuong .claude/archive/. Cua ra do chi an toan neu con dam
bao duoc rang rao chan van con. Xoa mot ham rao chan di ma van xuoi da nam
duoi archive/ la MAT KIEN THUC LANG LE: khong ai thay, va bay quay lai.

CHAY (tu goc repo):    "D:/Dev/conda-envs/py312/python.exe" .claude/guard_check.py
Exit code 1 khi thieu rao chan -> cam duoc vao CI / pre-commit hook.
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# --- CAU HINH: sua khoi nay cho dung du an ----------------------------------
SOURCE_GLOBS = ["lib/**/*.dart", "tool/**/*.dart", "test/**/*.dart",
                "windows/runner/*.cpp"]           # noi rao chan phai ton tai
TEST_GLOBS   = ["test/**/*.dart"]                 # noi tim test bug_<N>
# test/ nam trong glob co chu y: nhieu rao chan cua du an nay la test khoa
# bat bien tren file da sinh (trad2simp.tsv, SudachiVariants.txt, manifest).
EXCLUDE_DIRS = ("node_modules", ".next", "dist", "build", ".git", ".venv")
BUGS     = os.path.join(ROOT, ".claude", "IMPORTANT_FIXED_BUGS.md")
ARCHIVE  = os.path.join(ROOT, ".claude", "archive", "FIXED_BUGS_guarded.md")
UNTESTED = os.path.join(ROOT, ".claude", "untested_guards.txt")
# ---------------------------------------------------------------------------

# Mot literal trong backtick la FILE khi no co dang thu/muc/ten.ext, hoac la
# ten.ext tran voi duoi cua file ma nguon (kiem theo basename trong SOURCE_GLOBS).
PATH_RE = re.compile(r"^[\w.\-\[\]]+(?:/[\w.\-\[\]]+)+\.\w+$")
NAME_RE = re.compile(r"^[\w\-\[\]]+(?:\.[\w\-]+)*\."
                     r"(?:js|jsx|mjs|cjs|ts|tsx|py|rb|go|rs|dart|java|kt|swift|cs|php|ipynb|cpp|h)$")


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
    """Tach rao chan tu o -> [("file", duong dan) | ("sym", ten)].

    `test/x_test.dart`           -> ("file", ...): kiem FILE con ton tai.
    `lib/mod.py::fn`             -> ("file", lib/mod.py) + ("sym", fn)
    `Cls.method()`, `cfg.rb (remove_const)`, `fn()` -> ("sym", ...)

    Dang duong dan phai duoc xet TRUOC cac pattern symbol: neu khong,
    `tests/x.test.js` roi vao pattern cuoi va bi boc ra "js" - ma "js" co mat
    o moi file nen check PASS GIA vinh vien, xoa file test cung khong thay.

    THU TU PATTERN SYMBOL: dang `(symbol)` phai duoc thu TRUOC dang `.method(`,
    neu khong thi `cfg.rb (remove_const)` bi boc ra "rb" va `util.dart (fixKey)`
    bi boc ra "dart".
    """
    out = []
    for lit in re.findall(r"`([^`]+)`", cell):
        if PATH_RE.match(lit) or NAME_RE.match(lit):
            out.append(("file", lit, None))
            continue
        head = lit.split("::", 1)[0].split(" ", 1)[0]
        file_scope = head if (PATH_RE.match(head) or NAME_RE.match(head)) else None
        if file_scope:
            out.append(("file", file_scope, None))
        for pat in (r"::(\w+[!?]?)", r"\((\w+[!?]?)\)", r"\.(\w+[!?]?)\s*\(",
                    r"^(\w+[!?]?)\s*\(", r"\.(\w+[!?]?)$"):
            m = re.search(pat, lit)
            if m:
                out.append(("sym", m.group(1), file_scope))
                break
    return out


def untested_issues(rows, test_blob):
    """Ratchet: moi bay [OK] phai co test mang `bug_<N>`, tru danh sach cu."""
    ok_ids = {str(num) for num, _, level, _ in rows if level == "OK"}
    tested = {k for k in ok_ids if re.search(r"\bbug_%s(?!\d)" % re.escape(k), test_blob)}
    untested = ok_ids - tested
    allowed = {ln.split("#")[0].strip() for ln in read(UNTESTED).splitlines()} - {""}
    key_fn = lambda k: (len(k), k)
    issues = ["bay #%s [OK] nhung khong co test nao mang `bug_%s`" % (k, k)
              for k in sorted(untested - allowed, key=key_fn)]
    issues += ["untested_guards.txt ghi #%s nhung bay do da co test hoac khong con [OK]: xoa dong do" % k
               for k in sorted(allowed - untested, key=key_fn)]
    return issues, len(allowed)


def main():
    # Console Windows (cp1252...) khong in duoc ten bay tieng Viet: khong co dong
    # nay thi dung nhanh bao loi lai crash UnicodeEncodeError va mat thong bao.
    try:
        sys.stdout.reconfigure(errors="replace")
    except AttributeError:
        pass
    md = read(BUGS)
    if not md:
        sys.exit("Khong doc duoc %s" % BUGS)
    rows = parse_rows(md)
    if not rows:
        sys.exit("Khong tim thay Bang bay trong %s" % BUGS)

    files = []
    for g in SOURCE_GLOBS:
        files += glob.glob(os.path.join(ROOT, g), recursive=True)
    files = [p for p in set(files)
             if not any(d in p.replace("\\", "/").split("/") for d in EXCLUDE_DIRS)]
    if not files:
        sys.exit("SOURCE_GLOBS khong khop file nao - sua cau hinh dau script.")
    by_rel = {os.path.relpath(p, ROOT).replace("\\", "/"): read(p) for p in sorted(files)}
    blob = "\n".join(by_rel.values())
    basenames = {os.path.basename(p) for p in files}

    test_files = []
    for g in TEST_GLOBS:
        test_files += glob.glob(os.path.join(ROOT, g), recursive=True)
    test_blob = "\n".join(read(p) for p in sorted(set(test_files)))

    missing = []
    print("KIEM RAO CHAN  (%d bay trong bang, %d file nguon)" % (len(rows), len(files)))
    print("-" * 78)
    for num, name, level, cell in rows:
        if level == "NONE":
            continue
        names = guard_names(cell)
        if not names:
            missing.append((num, name, "(khong tach duoc rao chan tu: %s)" % cell))
            continue
        for kind, val, file_scope in names:
            if kind == "file":
                found = (os.path.isfile(os.path.join(ROOT, val)) if "/" in val
                         else val in basenames)
                if not found:
                    missing.append((num, name, "file " + val))
            else:
                if file_scope:
                    scoped = "\n".join(
                        txt for rel, txt in by_rel.items()
                        if rel == file_scope or rel.endswith("/" + file_scope)
                    )
                else:
                    scoped = blob
                if not re.search(r"\b%s(?!\w)" % re.escape(val), scoped):
                    missing.append((num, name, val))

    for num, name, fn in missing:
        print("  THIEU  bay #%-2d %-46s -> %s" % (num, name[:46], fn))

    n_ok   = sum(1 for r in rows if r[2] == "OK")
    n_part = sum(1 for r in rows if r[2] == "PART")
    n_none = sum(1 for r in rows if r[2] == "NONE")
    n_arch = len(re.findall(r"^### ", read(ARCHIVE), re.M))
    print("  [OK]   da co rao chan : %d bay   (archive giu %d muc)" % (n_ok, n_arch))
    print("  [PART] mot phan       : %d bay" % n_part)
    print("  [NONE] chua co        : %d bay  <- co hoi viet rao chan moi" % n_none)
    print("-" * 78)

    if n_ok != n_arch:
        print("LECH: %d bay danh dau OK nhung archive co %d muc." % (n_ok, n_arch))
        print("  -> moi bay [OK] phai co dung mot muc van xuoi trong archive.")
        return 1
    if missing:
        print("HONG: %d rao chan neu trong bang KHONG CO trong code." % len(missing))
        print("  -> hoac viet lai ham do, hoac keo bay tu archive/ ve va ha xuong [NONE].")
        return 1
    gaps, n_base = untested_issues(rows, test_blob)
    print("  test mang ID bay: %d/%d bay [OK] (baseline con %d)" % (n_ok - n_base, n_ok, n_base))
    for issue in gaps:
        print("  TEST   " + issue)
    if gaps:
        print("HONG: moi bay [OK] moi phai co test mang `bug_<N>`.")
        return 1
    print("OK: moi rao chan neu trong bang deu con trong code.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
