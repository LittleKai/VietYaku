#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Crawl từ điển Mazii (javi = Nhật→Việt) cho toàn bộ từ khóa trong JaViDict.txt.

Nguồn danh sách từ : data/jp/JaViDict.txt (key trước dấu '=' của mỗi dòng).
API                : POST https://mazii.net/api/search  (giống lib/features/translation/data/mazii_api.dart)
Lưu kết quả        : SQLite data/jp/MaziiDict.db — mỗi từ 1 row, word là PRIMARY KEY.
                     Chỉ lưu ĐÚNG 1 entry có 'word' trùng khít từ input (giống app: r['word'] == word).
                     Không có entry khớp → status 'no_match', KHÔNG lưu payload.

RESUME KHÔNG TRÙNG LẶP
    Mỗi từ crawl xong commit ngay vào DB. Khi chạy lại, script đọc các word đã có
    và bỏ qua → dừng bất cứ lúc nào (Ctrl+C / tắt máy) rồi chạy lại là tiếp tục
    đúng chỗ dở, không gọi lại API cho từ đã xong.

    Mặc định BỎ QUA cả từ 'error'. Dùng --retry-errors để crawl lại riêng các từ lỗi.

MIGRATE DỮ LIỆU CŨ
    Các row 'ok' crawl trước đây có payload là MẢNG nhiều entry (limit cũ = 10).
    Dùng --migrate để chuyển sang định dạng mới (giữ 1 entry khớp / no_match),
    KHÔNG gọi mạng.

Chạy (env conda py312 — KHÔNG dùng Python hệ thống):
    D:\\Dev\\conda-envs\\py312\\python.exe .claude\\code\\mazii_crawler.py
    D:\\Dev\\conda-envs\\py312\\python.exe .claude\\code\\mazii_crawler.py --limit 500 --delay 0.5
    D:\\Dev\\conda-envs\\py312\\python.exe .claude\\code\\mazii_crawler.py --retry-errors
    D:\\Dev\\conda-envs\\py312\\python.exe .claude\\code\\mazii_crawler.py --migrate
    D:\\Dev\\conda-envs\\py312\\python.exe .claude\\code\\mazii_crawler.py --stats
"""

import argparse
import json
import os
import signal
import sqlite3
import sys
import time

import requests

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))  # .claude/code -> VietYaku
DEFAULT_WORDS = os.path.join(PROJECT_ROOT, "data", "jp", "JaViDict.txt")
DEFAULT_DB = os.path.join(PROJECT_ROOT, "data", "jp", "MaziiDict.db")

API_URL = "https://mazii.net/api/search"
HEADERS = {
    "Content-Type": "application/json",
    "Accept": "application/json",
    "User-Agent": "VietYaku-crawler/1.0",
}

# Cờ dừng mềm: SIGINT/SIGTERM chỉ set cờ, để vòng lặp kết thúc từ hiện tại rồi thoát sạch.
_STOP = False


def _request_stop(signum, frame):
    global _STOP
    _STOP = True
    print("\n[!] Nhận tín hiệu dừng — hoàn tất từ hiện tại rồi thoát...", flush=True)


def open_db(path):
    conn = sqlite3.connect(path)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS results (
            word        TEXT PRIMARY KEY,
            status      TEXT NOT NULL,          -- ok | empty | no_match | error
            http_status INTEGER,
            found       INTEGER,                -- 1 nếu ok (đã khớp), ngược lại 0
            payload     TEXT,                   -- JSON entry khớp input (chỉ khi ok)
            error       TEXT,
            fetched_at  TEXT
        )
        """
    )
    conn.commit()
    return conn


def load_words(path):
    """Đọc key (phần trước dấu '=' đầu tiên) của mỗi dòng, giữ thứ tự, bỏ trùng."""
    words = []
    seen = set()
    with open(path, "r", encoding="utf-8-sig") as f:  # utf-8-sig: bỏ BOM ở dòng đầu
        for line in f:
            line = line.rstrip("\n").rstrip("\r")
            if not line:
                continue
            key = line.split("=", 1)[0].strip()
            if not key or key in seen:
                continue
            seen.add(key)
            words.append(key)
    return words


def already_done(conn, retry_errors):
    """Tập từ coi như đã xử lý → sẽ bỏ qua. Nếu retry_errors thì không tính 'error' là xong."""
    if retry_errors:
        rows = conn.execute("SELECT word FROM results WHERE status != 'error'")
    else:
        rows = conn.execute("SELECT word FROM results")
    return {r[0] for r in rows}


def _find_match(results, word):
    """Entry đầu tiên khớp khít từ input.

    Key trong JaViDict phần lớn là cách đọc hiragana; Mazii để chữ Hán ở 'word' còn
    cách đọc ở 'phonetic' (có thể nhiều âm cách nhau bởi space). Vì vậy khớp khi:
      - r['word'] == word, HOẶC
      - word nằm trong r['phonetic'].split().
    """
    for r in results:
        if not isinstance(r, dict):
            continue
        if r.get("word") == word:
            return r
        ph = r.get("phonetic")
        if isinstance(ph, str) and word in ph.split():
            return r
    return None


def fetch(session, word, limit, timeout):
    """Gọi Mazii 1 lần. Trả (status, http_status, found, payload_json_or_None, error_or_None).

    Chỉ giữ entry khớp khít từ input (word hoặc phonetic — xem _find_match).
    Mazii có trả kết quả nhưng không entry nào khớp → 'no_match', không lưu payload.
    """
    body = {"dict": "javi", "type": "word", "query": word, "limit": limit, "page": 1}
    res = session.post(API_URL, json=body, headers=HEADERS, timeout=timeout)
    if res.status_code != 200:
        return ("error", res.status_code, None, None, f"HTTP {res.status_code}")
    try:
        data = res.json()
    except ValueError as e:
        return ("error", res.status_code, None, None, f"JSON decode: {e}")
    if not isinstance(data, dict) or data.get("status") != 200:
        return ("error", res.status_code, None, None, f"API status: {data.get('status') if isinstance(data, dict) else 'n/a'}")
    results = data.get("data")
    if not isinstance(results, list) or len(results) == 0:
        return ("empty", res.status_code, 0, None, None)
    match = _find_match(results, word)
    if match is not None:
        return ("ok", res.status_code, 1, json.dumps(match, ensure_ascii=False), None)
    # Không có entry khớp khít → lấy entry đầu tiên (status 'fallback' để còn phân biệt).
    first = next((r for r in results if isinstance(r, dict)), None)
    if first is None:
        return ("empty", res.status_code, 0, None, None)
    return ("fallback", res.status_code, 1, json.dumps(first, ensure_ascii=False), None)


def upsert(conn, word, status, http_status, found, payload, error):
    conn.execute(
        "INSERT OR REPLACE INTO results (word, status, http_status, found, payload, error, fetched_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?)",
        (word, status, http_status, found, payload, error, time.strftime("%Y-%m-%dT%H:%M:%S")),
    )
    conn.commit()


def migrate(conn):
    """Chuyển các row 'ok' định dạng cũ (payload = mảng nhiều entry) sang định dạng mới,
    KHÔNG gọi mạng. Chỉ đụng cột status/found/payload; giữ nguyên http_status/error/fetched_at.

    - payload là mảng và có entry word==row.word → giữ entry đó (object), found=1.
    - payload là mảng nhưng không entry nào khớp, hoặc payload rỗng/hỏng → status='no_match'.
    - payload đã là object (định dạng mới) → bỏ qua.
    """
    rows = conn.execute("SELECT word, payload FROM results WHERE status = 'ok'").fetchall()
    converted = fallback = nomatch = skipped = 0
    for word, payload in rows:
        try:
            data = json.loads(payload) if payload else None
        except (ValueError, TypeError):
            data = None
        if isinstance(data, dict):  # đã là object định dạng mới
            skipped += 1
            continue
        if isinstance(data, list):
            match = _find_match(data, word)
            if match is not None:
                conn.execute(
                    "UPDATE results SET status='ok', found=1, payload=? WHERE word=?",
                    (json.dumps(match, ensure_ascii=False), word),
                )
                converted += 1
                continue
            first = next((r for r in data if isinstance(r, dict)), None)
            if first is not None:
                conn.execute(
                    "UPDATE results SET status='fallback', found=1, payload=? WHERE word=?",
                    (json.dumps(first, ensure_ascii=False), word),
                )
                fallback += 1
                continue
        conn.execute(
            "UPDATE results SET status='no_match', found=0, payload=NULL WHERE word=?",
            (word,),
        )
        nomatch += 1
    conn.commit()
    print(f"[migrate] {len(rows)} row 'ok' — convert={converted} fallback={fallback} no_match={nomatch} bỏ_qua(đã object)={skipped}", flush=True)


def print_stats(conn, total_words=None):
    rows = dict(conn.execute("SELECT status, COUNT(*) FROM results GROUP BY status").fetchall())
    ok = rows.get("ok", 0)
    fb = rows.get("fallback", 0)
    empty = rows.get("empty", 0)
    nomatch = rows.get("no_match", 0)
    err = rows.get("error", 0)
    done = ok + fb + empty + nomatch + err
    tail = f" / {total_words} từ nguồn" if total_words else ""
    print(f"[stats] đã xử lý {done}{tail} — ok={ok} fallback={fb} empty={empty} no_match={nomatch} error={err}", flush=True)


def main():
    ap = argparse.ArgumentParser(description="Crawl Mazii (javi) theo danh sách JaViDict, resume an toàn.")
    ap.add_argument("--words", default=DEFAULT_WORDS, help="File nguồn từ khóa (mặc định data/jp/JaViDict.txt)")
    ap.add_argument("--db", default=DEFAULT_DB, help="File SQLite lưu kết quả (mặc định data/jp/MaziiDict.db)")
    ap.add_argument("--limit", type=int, default=1, help="Số kết quả xin mỗi từ (param 'limit' của API; chỉ giữ entry khớp input)")
    ap.add_argument("--delay", type=float, default=0.4, help="Nghỉ giữa 2 request (giây), tránh spam")
    ap.add_argument("--timeout", type=float, default=15.0, help="Timeout mỗi request (giây)")
    ap.add_argument("--max-retries", type=int, default=3, help="Số lần thử lại khi lỗi mạng/tạm thời mỗi từ")
    ap.add_argument("--run-limit", type=int, default=0, help="Số từ tối đa crawl trong LẦN chạy này (0 = không giới hạn)")
    ap.add_argument("--retry-errors", action="store_true", help="Crawl lại các từ đang ở trạng thái 'error'")
    ap.add_argument("--retry-nomatch", action="store_true", help="Crawl lại CHỈ các từ đang 'no_match' (không đụng từ chưa crawl)")
    ap.add_argument("--migrate", action="store_true", help="Chuyển row 'ok' cũ (payload mảng) sang định dạng mới rồi thoát (không gọi mạng)")
    ap.add_argument("--stats", action="store_true", help="Chỉ in thống kê DB rồi thoát")
    args = ap.parse_args()

    conn = open_db(args.db)

    if args.migrate:
        migrate(conn)
        print_stats(conn)
        return

    if args.stats:
        try:
            total = len(load_words(args.words))
        except OSError:
            total = None
        print_stats(conn, total)
        return

    if not os.path.isfile(args.words):
        print(f"[x] Không thấy file nguồn: {args.words}", file=sys.stderr)
        sys.exit(1)

    signal.signal(signal.SIGINT, _request_stop)
    signal.signal(signal.SIGTERM, _request_stop)

    words = load_words(args.words)
    if args.retry_nomatch:
        todo = [r[0] for r in conn.execute("SELECT word FROM results WHERE status='no_match' ORDER BY word")]
        print(f"[i] retry-nomatch: {len(todo)} từ 'no_match' sẽ crawl lại", flush=True)
    else:
        done = already_done(conn, args.retry_errors)
        todo = [w for w in words if w not in done]
        print(f"[i] Nguồn {len(words)} từ | đã xong {len(done)} | còn lại {len(todo)}", flush=True)
    if not todo:
        print("[i] Không còn từ nào để crawl. Xong.", flush=True)
        print_stats(conn, len(words))
        return

    session = requests.Session()
    processed = new_ok = new_fallback = new_empty = new_nomatch = new_err = 0
    start = time.time()

    for word in todo:
        if _STOP:
            break
        if args.run_limit and processed >= args.run_limit:
            print(f"[i] Đạt --run-limit {args.run_limit}, dừng lần chạy này.", flush=True)
            break

        status = http_status = found = payload = error = None
        for attempt in range(1, args.max_retries + 1):
            try:
                status, http_status, found, payload, error = fetch(session, word, args.limit, args.timeout)
                # Lỗi tạm thời (mạng/HTTP 5xx/429) → thử lại; lỗi 'ok'/'empty'/'no_match'/4xx-khác → chấp nhận.
                transient = status == "error" and (http_status is None or http_status >= 500 or http_status == 429)
                if not transient:
                    break
            except requests.RequestException as e:
                status, http_status, found, payload, error = "error", None, None, None, f"{type(e).__name__}: {e}"
            if attempt < args.max_retries:
                time.sleep(min(2.0 * attempt, 8.0))  # backoff tuyến tính, tối đa 8s

        upsert(conn, word, status, http_status, found, payload, error)
        processed += 1
        if status == "ok":
            new_ok += 1
        elif status == "fallback":
            new_fallback += 1
        elif status == "empty":
            new_empty += 1
        elif status == "no_match":
            new_nomatch += 1
        else:
            new_err += 1

        if processed % 50 == 0:
            rate = processed / max(time.time() - start, 1e-6)
            remaining = len(todo) - processed
            eta_min = (remaining / rate) / 60 if rate > 0 else 0
            print(
                f"[{processed}/{len(todo)}] ok={new_ok} fallback={new_fallback} empty={new_empty} no_match={new_nomatch} err={new_err} "
                f"| {rate:.1f} từ/s | ETA ~{eta_min:.0f} phút | cuối: {word}",
                flush=True,
            )

        time.sleep(args.delay)

    print(f"[done] lần này crawl {processed} từ — ok={new_ok} fallback={new_fallback} empty={new_empty} no_match={new_nomatch} err={new_err}", flush=True)
    print_stats(conn, len(words))


if __name__ == "__main__":
    main()
