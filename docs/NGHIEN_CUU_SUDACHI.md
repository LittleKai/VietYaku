# Nghiên cứu Sudachi — tính năng áp dụng được cho VietYaku (tiếng Nhật)

> Tài liệu nghiên cứu, không phải SPEC build. Nguồn khảo sát:
> `D:\Dev\2.reference_pj\language-ref\.dict\jp\Sudachi` (Sudachi Java, Works Applications, license Apache-2.0).
> Ngày khảo sát: 2026-07-19.

---

## 1. Sudachi là gì

Sudachi là bộ phân tích hình thái tiếng Nhật (morphological analyzer) viết bằng Java:

- **Kiến trúc lõi:** từ điển nhị phân (double-array trie, format UniDic) → xây lattice mọi cách tách từ → Viterbi chọn đường đi chi phí thấp nhất (connection cost giữa các POS) → plugin hậu xử lý.
- **Pipeline plugin** (khai báo trong `src/main/resources/sudachi.json`):
  1. `inputTextPlugin` — chuẩn hoá văn bản **trước khi tra từ điển** (giữ bảng offset về văn bản gốc).
  2. `oovProviderPlugin` — sinh token cho từ ngoài từ điển (OOV).
  3. `pathRewritePlugin` — sửa lại chuỗi token sau khi tách (gộp số, gộp katakana…).
- **3 chế độ tách:** A (đơn vị ngắn ~UniDic), B (trung), C (cụm dài nhất/named entity). Cùng một câu tách được ở nhiều độ mịn.
- **Từ điển SudachiDict** (repo ngoài, cũng Apache-2.0): mỗi entry có 18 trường CSV, đáng chú ý: trường 11 **読み (reading, katakana)** và trường 12 **正規化表記 (normalized form)** — xem `docs/user_dict.md` trong repo Sudachi.

### Đối chiếu nhanh với VietYaku

| | Sudachi | VietYaku hiện tại |
|---|---|---|
| Chọn cụm | Lattice + Viterbi (cost) | Greedy longest-match / longestPhrase(4) |
| Cấu trúc tra | Double-array trie | `HashMap` + `maxLenByFirstUnit` (đã chốt, không bàn lại) |
| Chuẩn hoá input | Plugin + `rewrite.def`, có offset map | `normalizeDisplayText()` chỉ cho **hiển thị** passthrough (`lib/core/cjk.dart:76`) |
| OOV | Plugin theo category ký tự | Fallback từng rune: Hán → Hán Việt, kana → passthrough (`translation_engine.dart:95`) |
| POS / reading | Có | Không |

Kết luận tổng quát: **phần lattice/Viterbi/POS không áp dụng được** (trái thiết kế đã chốt: không trie, không cost model, không AI). Phần giá trị nhất cho VietYaku là **hai lớp plugin bao quanh**: chuẩn hoá input trước khi tra, và gộp token sau khi tra — cả hai đều là thuật toán nhỏ, thuần Dart, không đụng engine.

---

## 2. Tính năng áp dụng được

### 2.1. Chuẩn hoá trường âm — `ProlongedSoundMarkInputTextPlugin` ⭐ P1

**Sudachi làm gì** (`sudachi.json:6-8`): coi các ký tự `ー - ⁓ 〜 〰` là trường âm, thay tất cả về `ー` và **rút chuỗi lặp về 1 ký tự**.

**Giá trị cho VietYaku:** text light novel/web novel đầy dạng kéo dài `あーーー`, `スーーーパー`, hoặc dùng nhầm `〜`/`-` thay `ー` → hiện tại trượt hết match VietPhrase. Rút `ーー…` về `ー` trước khi tra tăng hit rate ngay.

**Áp dụng:** bước tiền xử lý chuỗi trước `translate()`, chỉ mode Nhật. Cần bảng map offset (xem §3.1). Effort: nhỏ.

### 2.2. Bỏ yomigana trong ngoặc — `IgnoreYomiganaPlugin` ⭐ P1

**Sudachi làm gì** (`sudachi.json:9-12`): sau một chữ Hán, nếu gặp `(かな)` / `（かな）` dài ≤ 4 ký tự kana thì bỏ phần ngoặc khi tra: `空腹(すきばら)` → tra `空腹`.

**Giá trị cho VietYaku:** raw novel Nhật rất hay chèn furigana kiểu này; hiện tại phần ngoặc thành passthrough xen giữa làm gãy cụm match. Điều kiện "ngay sau kanji + toàn kana + ≤ 4 ký tự" đủ an toàn để không ăn nhầm ngoặc thoại.

**Áp dụng:** cùng tầng tiền xử lý với 2.1. Có thể thêm setting giữ/bỏ hiển thị phần yomigana. Effort: nhỏ.

### 2.3. Gộp run katakana OOV — `JoinKatakanaOovPlugin` ⭐ P1

**Sudachi làm gì** (`sudachi.json:25-28`): sau khi tách, các mảnh katakana ngắn/OOV liền kề được gộp thành 1 danh từ (minLength 3) — vì tên riêng nước ngoài (nhân vật, địa danh) thường là chuỗi katakana không có trong từ điển.

**Giá trị cho VietYaku:** đây là điểm đau thực tế — tên nhân vật katakana không có trong Names bị vỡ vụn thành từng ký tự passthrough. Gộp run katakana liên tiếp **không match dict nào** thành 1 token `unmatched` duy nhất:
- hiển thị gọn, tô màu 1 cụm;
- click tra Mazii/Google được nguyên tên;
- thêm vào UserDict/Names 1 phát đúng nguyên cụm.

**Áp dụng:** hậu xử lý danh sách `Token` trong `TranslationEngine` (hoặc bước sau `translate()`): gộp các token liên tiếp `kind == unmatched/passthrough` mà toàn ký tự katakana (`isKanaCodePoint` dải 30A0–30FF/31F0–31FF + `ー`). Lưu ý đừng gộp xuyên qua token `matched`. Effort: nhỏ, không đụng thuật toán match.

### 2.4. Gộp & chuẩn hoá số — `JoinNumericPlugin` P2

**Sudachi làm gì** (`sudachi.json:23-24`): gộp chuỗi chữ số thành 1 token, kể cả **số kanji** (`一二三`, có đơn vị `十百千万億兆`), tuỳ chọn normalize về số Ả Rập (`enableNormalize: true`): `三百二十五` → `325`, `1,000` → `1000`.

**Giá trị cho VietYaku:** số kanji trong novel (`三百人`, `五十メートル`) hiện rơi vào Hán Việt fallback từng chữ ("tam bách nhị thập ngũ" thay vì "325"). Một converter kanji-numeral → Arabic là thuật toán độc lập ~50-80 dòng Dart, có thể bật/tắt bằng setting.

**Áp dụng:** hậu xử lý token (như 2.3): phát hiện run ký tự thuộc tập số kanji + chữ số, thay `rawValue` bằng số đã đổi. Cẩn thận từ đã có trong VietPhrase (`一人` = "một người") — chỉ áp cho run **không match** dict. Effort: vừa.

### 2.5. Chuẩn hoá ký tự kiểu `rewrite.def` P2

**Sudachi làm gì** (`DefaultInputTextPlugin` + `src/main/resources/rewrite.def`): lowercase + NFKC, **nhưng** với 2 danh sách ngoại lệ:
- *ignore list* (dòng 3-838): ký tự không được NFKC đụng vào (số La Mã Ⅰ-Ⅻ, bộ thủ CJK ⺀-⺮…);
- *replace list* (dòng 839+): thay thế trực tiếp, ưu tiên hơn NFKC — chủ yếu **halfwidth katakana + dakuten → fullwidth**: `ｶﾞ→ガ`, `ﾊﾟ→パ`, `うﾞ→ゔ`…

**Giá trị cho VietYaku:** text copy từ web/game cũ hay chứa halfwidth katakana `ｱｲｳｴｵ` — hiện tại nằm ngoài `isKanaCodePoint` (dải FF66–FF9F chưa được nhận), thành passthrough và không tra được. Chuẩn hoá halfwidth→fullwidth **ở tầng lookup** (không chỉ hiển thị) sửa được lớp lỗi này. Mô hình "NFKC + ignore + replace" cũng đúng tinh thần quy tắc vàng jp_valid_kanji sẵn có của repair pipeline: **chuẩn hoá có danh sách chặn, không chuẩn hoá mù**.

**Áp dụng:** cùng tầng tiền xử lý §3.1. Không cần bê cả `rewrite.def`; chỉ cần bảng halfwidth-kana (kể cả dạng 2 ký tự có dakuten/handakuten) + fullwidth Latin (đã có phép trừ 0xFEE0 trong `normalizeDisplayText`). Effort: vừa.

### 2.6. Khai thác SudachiDict làm dữ liệu build-time P3

Hai trường trong lexicon CSV của SudachiDict dùng được **offline, lúc dev**, theo đúng pattern `tool/build_simp2jp.dart`:

**a) Normalized form (trường 12) → bảng biến thể → tăng hit rate VietPhrase.**
SudachiDict chuẩn hoá okurigana và biến thể chữ: `打込む→打ち込む`, `附属→付属`, `かつ丼→カツ丼`, `ヴァイオリン→バイオリン`. Sinh file `variant→canonical` (chỉ giữ cặp mà *canonical có trong VietPhrase còn variant thì không*), lúc tra: miss → thử dạng canonical. Giải quyết lớp miss "từ điển có 打ち込む nhưng text viết 打込む".

**b) Reading (trường 11) → bảng word→reading (katakana) → furigana per-token.**
Backlog hiện ghi "furigana cần MeCab — không có port Dart thuần". Bảng tra tĩnh từ SudachiDict phủ được **từ nguyên dạng có trong dict** — không giải quyết được thể chia (活用) và từ đa âm đọc theo ngữ cảnh (生: せい/なま/いき…), nhưng đủ cho tooltip reading của token matched. Ghi rõ giới hạn này nếu làm.

**Ràng buộc:** SudachiDict tải riêng (~GB dạng CSV đầy đủ; bản small/core nhỏ hơn), Apache-2.0 — cần dòng attribution nếu nhúng dữ liệu dẫn xuất. Chỉ chạy lúc dev, output là asset tĩnh; **không** đưa SudachiDict vào app.

### 2.7. Ý tưởng tham khảo thêm (không ưu tiên)

- **Split mode A/B/C** → tính năng "tách nhỏ cụm": click token matched dài để re-split thành các từ con (tra đệ quy chính dict hiện có). Tinh thần multi-granularity của Sudachi, không cần lattice.
- **Category ký tự (`char.def`)** → nếu làm 2.3/2.4, nên thêm helper phân loại run ký tự (HIRAGANA/KATAKANA/KANJI/NUMERIC/ALPHA) vào `lib/core/cjk.dart` thay vì if-else rải rác — `char.def` là danh sách dải Unicode tham khảo tốt (kể cả các ký tự nhỏ ㇰ-ㇿ 31F0–31FF đã có trong `isKanaCodePoint`).

---

## 3. Điểm kỹ thuật phải lưu ý khi áp dụng

### 3.1. Offset mapping — điều kiện tiên quyết cho mọi mục "chuẩn hoá input"

Sudachi không chuẩn hoá phá huỷ: `UTF8InputText` giữ **bảng ánh xạ từng vị trí văn bản đã chuẩn hoá → vị trí văn bản gốc**, nên token luôn trỏ đúng về text gốc.

VietYaku có ràng buộc y hệt: `Token.sourceStart` là offset UTF-16 vào **text gốc**, UI (`token_text_view`, copy/paste, highlight) phụ thuộc vào nó. Vậy các mục 2.1/2.2/2.5 **bắt buộc** làm theo mô hình:

```
text gốc ──chuẩn hoá──▶ text tra (norm) + List<int> normToOrig (độ dài = norm.length + 1)
translate(norm) ──▶ token có offset theo norm ──map ngược──▶ sourceStart/source theo text gốc
```

Nếu không làm bảng map thì highlight/copy sẽ lệch — đây là rủi ro chính, còn bản thân các phép thay thế đều đơn giản.

### 3.2. Thứ tự pipeline đề xuất

```
input gốc
  → [P1] rút trường âm (2.1) → bỏ yomigana (2.2) → [P2] halfwidth→fullwidth (2.5)
  → TranslationEngine.translate()   (không đổi)
  → [P1] gộp katakana OOV (2.3) → [P2] gộp/đổi số (2.4)
  → tokens (offset đã map về text gốc)
```

Tất cả là hàm thuần trên `String`/`List<Token>` → test đơn vị dễ, không đụng thiết kế đã chốt của engine, chỉ áp dụng khi `TranslationMode.japanese` (trừ 2.5 phần fullwidth Latin có thể dùng chung với mode Trung).

### 3.3. Những gì KHÔNG nên bê sang

| Thành phần Sudachi | Lý do không áp dụng |
|---|---|
| Lattice + Viterbi, connection cost | Trái quyết định đã chốt (HashMap greedy, không cost model); cần ma trận UniDic ~vài chục MB |
| POS, `InhibitConnectionPlugin`, `MeCabOovProviderPlugin` | Phụ thuộc lattice + POS — VietYaku không có tầng này |
| Format user dict 18 trường / cost −32767..32767 | UserDict `key=value` + ưu tiên theo bậc (UserDict > Names > VietPhrase) đã đủ, đơn giản hơn |
| Double-array trie, dictionary binary format của Sudachi | `.vydc` custom đã chốt |
| Sudachi qua FFI (sudachi.rs) | Kéo native dependency, ngược tiêu chí offline thuần Dart; chỉ cân nhắc nếu v2 cần tách từ chuẩn thực sự |

---

## 4. Bảng ưu tiên đề xuất

| # | Tính năng | Nguồn Sudachi | Giá trị | Effort | Ưu tiên |
|---|---|---|---|---|---|
| 2.3 | Gộp run katakana OOV thành 1 token | `JoinKatakanaOovPlugin` | Cao (tên riêng novel) | Nhỏ | **P1** |
| 2.1 | Rút/chuẩn hoá trường âm `ーー〜` | `ProlongedSoundMarkInputTextPlugin` | Cao | Nhỏ (+3.1) | **P1** |
| 2.2 | Bỏ yomigana `漢字(かな)` khi tra | `IgnoreYomiganaPlugin` | Cao | Nhỏ (+3.1) | **P1** |
| 2.5 | Halfwidth kana → fullwidth ở tầng lookup | `DefaultInputTextPlugin` + `rewrite.def` | Vừa | Vừa | P2 |
| 2.4 | Gộp + đổi số kanji → Arabic | `JoinNumericPlugin` | Vừa | Vừa | P2 |
| 2.6a | Bảng biến thể okurigana từ SudachiDict | SudachiDict normalized_form | Cao nhưng cần đo | Lớn (tool dev) | P3 |
| 2.6b | Bảng word→reading cho furigana tĩnh | SudachiDict reading | Vừa (có giới hạn) | Lớn (tool dev) | P3 |
| 2.7 | Re-split token dài; helper category ký tự | Split modes, `char.def` | Thấp | Nhỏ | Backlog |

Nhóm P1 độc lập nhau, mỗi cái một hàm thuần + test riêng; làm chung một phase được vì cùng cần hạ tầng offset map (3.1) — riêng 2.3 không cần offset map (hậu xử lý token).

---

## 5. Trạng thái triển khai (2026-07-19)

P2 + P3 đã triển khai, tất cả bật/tắt được trong Cài đặt (mặc định bật, chỉ tác dụng mode Nhật):

| Mục | Triển khai | Setting |
|---|---|---|
| 2.5 Halfwidth kana → fullwidth (kèm offset map §3.1) | `lib/features/translation/domain/jp_input_normalizer.dart`, gọi trong `TranslationController.translate` | `normalizeHalfwidthKana` |
| 2.4 Gộp + đổi số kanji → Ả Rập | `lib/features/translation/domain/kanji_numeral.dart` (run ≥ 2 token hanViet/unmatched liền kề; parse fail giữ nguyên) | `joinKanjiNumerals` |
| 2.6a Bảng biến thể | `tool/build_sudachi_assets.dart` → `data/jp/SudachiVariants.txt` (~13,7k mục), merge DƯỚI VietPhrase trong `DictionaryRepository.loadAll`; đổi setting → nạp lại dict. Chỉ nhận biến thể chứa ≥1 chữ Hán hoặc thuần katakana ≥2 ký tự — biến thể thuần hiragana (し→四) phá match ngữ pháp, xem IMPORTANT_FIXED_BUGS 2026-07-19 | `sudachiVariants` |
| 2.6b Bảng reading | cùng tool → `data/jp/SudachiReadings.txt` (~44k mục, key có chữ Hán thuộc VietPhrase/Names/LacViet + các biến thể), fallback phát âm kana trong `LookupController` sau Nhật Việt | `sudachiReadings` |

| 2.7 Category ký tự (`char.def`) | `lib/core/cjk.dart`: enum `CjkCharCategory` (space/numeric/alpha/hiragana/katakana/kanjiNumeric/kanji/other), `charCategoryOf(cp)`, `categoryRunsOf(text)` (tách run theo rune), `kanjiNumericCodeUnits`; `kanji_numeral.dart` dùng làm membership. Dải theo char.def + halfwidth kana FF66–FF9F | không cần (helper thuần) |

Tool chạy lại khi muốn cập nhật SudachiDict: `dart run tool/build_sudachi_assets.dart` (cần mạng lần đầu, zip cache ở `build/sudachi_raw/`; nguồn chỉ có HTTP). Test: `test/sudachi_p2_test.dart`, `test/cjk_category_test.dart`. P1 (2.1/2.2/2.3) chưa làm — 2.3 (gộp katakana OOV) sẽ dùng `categoryRunsOf`/`CjkCharCategory.katakana` làm nền.

---

## 6. File tham chiếu trong repo Sudachi

- `src/main/resources/sudachi.json` — cấu hình pipeline mặc định (danh sách plugin + tham số).
- `src/main/resources/rewrite.def` — ignore list (dòng 1-838) + replace list halfwidth→fullwidth (dòng 839+).
- `src/main/resources/char.def` — dải Unicode → category (HIRAGANA/KATAKANA/KANJI/NUMERIC…), tham số OOV per-category.
- `src/main/resources/unk.def` — định nghĩa OOV per-category (kiểu MeCab).
- `docs/user_dict.md` — format 18 trường của dict source; mô tả chuẩn hoá ký tự (lowercase + NFKC + rewrite.def).
- `src/main/java/com/worksap/nlp/sudachi/` — `ProlongedSoundMarkInputTextPlugin.java`, `IgnoreYomiganaPlugin.java`, `JoinKatakanaOovPlugin.java`, `JoinNumericPlugin.java`, `DefaultInputTextPlugin.java`, `UTF8InputText*.java` (mô hình offset mapping).
- README.md — mô tả split mode A/B/C, chuẩn hoá biến thể (打込む→打ち込む, かつ丼→カツ丼, 附属→付属).
