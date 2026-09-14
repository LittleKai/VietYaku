# Phát hành — VietYaku

**Last Updated:** 2026-09-14

> Chuyển nguyên văn từ `CLAUDE.md` (bản 1). Quy trình do skill
> `.claude/skills/build-and-release/` thực thi.

---


Mỗi bản release đi ra **hai nơi cùng lúc**, do skill `.claude/skills/build-and-release` lo:

| Kênh | Phục vụ | Nguồn |
|------|---------|-------|
| **GitHub Release** (`LittleKai/VietYaku`) | **Cập nhật trong app** — `lib/features/update/` gọi `releases/latest`, tự tìm asset chứa `windows` + đuôi `.zip` | Asset đính kèm release |
| **Backblaze B2** (bucket `alpha-studio`) | **Link tải trên web** — tool `giaiphapsangtao.com/studio/vietyaku` | `vietyaku-app/version.json` + `vietyaku-app/releases/VietYaku-windows-x64-v<version>.zip` |

- Cùng một file ZIP đi lên cả hai nơi; B2 thêm version vào tên object vì mọi bản nằm chung một prefix.
- `version.json` mang shape giống payload GitHub release (`tag_name`, `body`, `html_url`, `assets[]`) để backend Alpha Studio parse chung một kiểu.
- Phía web: `alpha-studio-backend` có `GET /api/vietyaku/releases/latest` fetch `version.json` rồi cache vào `SystemSetting` (key `vietyaku_latest_release`). Ra bản mới **không cần deploy lại** frontend hay backend.
- Đổi cấu trúc `version.json` hoặc tên object trên B2 → phải sửa cả `alpha-studio-backend/server/routes/vietyaku.js` và `alpha-studio/src/services/vietyakuReleaseService.ts` (repo `D:\Dev\NodeJS\alpha-studio`).
- Credential B2 (`B2_ACCESS_KEY_ID`, `B2_SECRET_ACCESS_KEY`, `B2_BUCKET_NAME`, `CDN_BASE_URL`) đọc từ `.env` — cùng giá trị với `alpha-studio-backend/.env`. **Không hardcode, không log, không commit.**

---

