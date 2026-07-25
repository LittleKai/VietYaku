#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Chuyển MaziiDict.db -> Mazii.txt (format Lạc Việt: key=value, \\n/\\t escaped).

Value tái tạo cách hiển thị của lib/features/translation/data/mazii_api.dart
(_format), nhưng BỎ chữ word lặp ở đầu (key đã là word). Đa dòng lưu bằng
escape literal \\n / \\t, giải mã bằng unescapeLacViet khi hiển thị.

Dùng:
  python mazii_db_to_txt.py [--limit N] [--all]
Mặc định --limit 500 (convert thử một phần).
"""
import argparse
import json
import os
import sqlite3

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DB = os.path.join(ROOT, "data", "jp", "MaziiDict.db")
OUT = os.path.join(ROOT, "data", "jp", "Mazii.txt")


def format_value(item):
    """Trả về chuỗi nghĩa đa dòng (chưa escape) hoặc None nếu rỗng."""
    lines = []
    phonetic = item.get("phonetic")
    han = item.get("han")
    header = " ".join(
        part
        for part in (
            f"\u300c{phonetic}\u300d" if phonetic else "",  # 「phonetic」
            f"(H\u00e1n: {han})" if han else "",
        )
        if part
    )
    if header:
        lines.append(header)

    means = item.get("means")
    if isinstance(means, list):
        for m in means[:5]:
            if not isinstance(m, dict):
                continue
            mean = m.get("mean")
            if not isinstance(mean, str) or not mean:
                continue
            kind = m.get("kind")
            lines.append(f"- ({kind}) {mean}" if kind else f"- {mean}")
            examples = m.get("examples")
            if isinstance(examples, list) and examples:
                ex = examples[0]
                if isinstance(ex, dict):
                    content = ex.get("content")
                    ex_mean = ex.get("mean")
                    if isinstance(content, str) and content:
                        lines.append(
                            f"  vd: {content} \u2192 {ex_mean}"
                            if isinstance(ex_mean, str) and ex_mean
                            else f"  vd: {content}"
                        )

    if not isinstance(means, list) or len(lines) <= (1 if header else 0):
        short_mean = item.get("short_mean")
        if isinstance(short_mean, str) and short_mean:
            lines.append(f"- {short_mean}")

    # Cần ít nhất 1 dòng nghĩa (không tính riêng header).
    if not lines or (header and len(lines) <= 1):
        return None
    return "\n".join(lines)


def escape(value):
    """Đa dòng -> literal \\n \\t để lưu 1 dòng (giống Lạc Việt)."""
    return value.replace("\t", "\\t").replace("\r", "").replace("\n", "\\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=500)
    ap.add_argument("--all", action="store_true")
    args = ap.parse_args()

    con = sqlite3.connect(DB)
    cur = con.cursor()
    q = (
        "SELECT word, payload FROM results "
        "WHERE found >= 1 AND payload IS NOT NULL AND payload != '' "
        "ORDER BY rowid"
    )
    if not args.all:
        q += f" LIMIT {args.limit}"

    written = skipped = 0
    seen = set()
    with open(OUT, "w", encoding="utf-8-sig", newline="") as f:  # BOM + CRLF
        for word, payload in cur.execute(q):
            if not word or word in seen:
                continue
            try:
                item = json.loads(payload)
            except Exception:
                skipped += 1
                continue
            if not isinstance(item, dict):
                skipped += 1
                continue
            value = format_value(item)
            if value is None:
                skipped += 1
                continue
            seen.add(word)
            f.write(f"{word}={escape(value)}\r\n")
            written += 1

    print(f"written={written} skipped={skipped} -> {OUT}")


if __name__ == "__main__":
    main()
