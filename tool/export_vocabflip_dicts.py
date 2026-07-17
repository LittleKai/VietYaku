# Export từ điển offline của VocabFlip (SQLite, gốc StarDict) sang format
# `key=value` mà VietYaku nạp được (UTF-8 BOM, CRLF, newline trong value
# escape thành literal `\n` như LacViet.txt).
#
# Chạy 1 lần lúc dev (không cần khi build app):
#   conda activate D:\Dev\conda-envs\py312
#   python tool/export_vocabflip_dicts.py
#
# Nguồn:  D:\Dev\NodeJS\alpha-studio\tools\vocabflip\assets\{ja_vi,zh_vi}_dict.db
#         (bảng words(id, word, definition), definition nhiều dòng markup StarDict)
# Đích:   data/jp/JaViDict.txt và data/cn/ZhViDict.txt trong dự án.
#         Chỉ tạo file MỚI, không đụng file gốc nào.

import sqlite3
from pathlib import Path

SRC_DIR = Path(r"D:\Dev\NodeJS\alpha-studio\tools\vocabflip\assets")
DATA_DIR = Path(__file__).resolve().parent.parent / "data"

EXPORTS = [
    ("ja_vi_dict.db", DATA_DIR / "jp" / "JaViDict.txt"),
    ("zh_vi_dict.db", DATA_DIR / "cn" / "ZhViDict.txt"),
]


# Không escape backslash vì unescapeLacViet phía app chỉ đổi `\n`/`\t`
# (giống semantics LacViet.txt).
def escape_value(definition: str) -> str:
    value = definition.replace("\r\n", "\n").replace("\r", "\n").strip()
    return value.replace("\t", "\\t").replace("\n", "\\n")


def export(db_path: Path, out_path: Path) -> None:
    con = sqlite3.connect(db_path)
    entries: dict[str, str] = {}
    skipped = 0
    for word, definition in con.execute("SELECT word, definition FROM words"):
        key = (word or "").strip()
        value = escape_value(definition or "")
        if not key or not value or "=" in key or "\n" in key:
            skipped += 1
            continue
        # Key trùng → gộp definition, phân cách bằng xuống dòng.
        if key in entries:
            entries[key] = entries[key] + "\\n" + value
        else:
            entries[key] = value
    con.close()

    with open(out_path, "w", encoding="utf-8-sig", newline="") as f:
        for key, value in entries.items():
            f.write(f"{key}={value}\r\n")
    print(f"{db_path.name} -> {out_path}: {len(entries)} entries, skipped {skipped}")


if __name__ == "__main__":
    for db_name, out_path in EXPORTS:
        export(SRC_DIR / db_name, out_path)
