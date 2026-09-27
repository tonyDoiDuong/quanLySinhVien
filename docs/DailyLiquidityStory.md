# NTA Daily Liquidity Story (MT5)

Chuỗi thanh khoản **ASIA → LONDON → NEW YORK** được cài đặt thành **một state machine xuyên suốt ngày giao dịch**,
không phải các tín hiệu Kill Zone rời rạc.

```
ASIA tạo liquidity → LONDON săn liquidity Asia → LONDON tạo liquidity mới
→ NEW YORK săn liquidity → DISPLACEMENT → MSS → FVG → RETRACE → STORY CONDITIONS COMPLETE
```

Indicator ưu tiên **câu chuyện thị trường**, không phát tín hiệu BUY/SELL. Hướng (bullish/bearish) chỉ xuất hiện
khi **Displacement + MSS** thực sự được xác nhận sau một liquidity sweep.

## Cấu trúc file

| File | Vai trò |
|---|---|
| `MQL5/Indicators/NTA/NTA_DailyLiquidityStory.mq5` | Indicator: inputs, buffers, vẽ, panel, xuất CSV |
| `MQL5/Include/NTA/DailyLiquidityStory/DLS_Types.mqh` | Enum state machine, struct Level / Leg / Day, text helpers |
| `MQL5/Include/NTA/DailyLiquidityStory/DLS_Engine.mqh` | **Engine** (không gọi hàm chart) – dùng lại được cho EA / backtest |
| `MQL5/Include/NTA/DailyLiquidityStory/DLS_Stats.mqh` | Thống kê A–L + xuất CSV mỗi ngày |
| `MQL5/Include/NTA/DailyLiquidityStory/DLS_Renderer.mqh` | Box Asia/London, level BSL/SSL, nhãn câu chuyện, story path, panel timeline |
| `tools/dls_stats.py` | Gộp nhiều CSV (M1/M5/M15…) và in bảng thống kê |

Cài đặt: copy thư mục `MQL5/` vào Data Folder của MT5 (File → Open Data Folder), compile
`NTA_DailyLiquidityStory.mq5` trong MetaEditor, gắn vào chart XAUUSD M1/M5/M15.

## Thời gian

Tất cả giờ session nhập theo **giờ New York**. `InpServerToNyHours` = giờ NY − giờ server
(broker GMT+3 theo DST Mỹ → `-7`). Ngày câu chuyện bắt đầu lúc `18:00` NY (mặc định).

| Mốc | Mặc định (NY) |
|---|---|
| Asia Kill Zone | 20:00 – 00:00 |
| London Kill Zone | 02:00 – 05:00 |
| NY liquidity window (theo dõi sweep) | 07:00 – 11:00 |
| NY development cutoff (disp / MSS / FVG / retrace) | 12:00 |
| Kết thúc đo MFE / MAE | 16:00 |
| Silver Bullet AM / PM / London | 10–11 / 14–15 / 03–04 (London tắt) |

## State machine

```
DAY_START → ASIA_BUILDING → ASIA_LOCKED → WAIT_LONDON
→ LONDON_MONITORING_ASIA → LONDON_BUILDING_LIQUIDITY (sau khi London đã lấy liquidity Asia)
→ LONDON_LOCKED → WAIT_NEW_YORK → NY_MONITORING_LIQUIDITY
→ NY_LIQUIDITY_SWEPT → WAIT_DISPLACEMENT → DISPLACEMENT_CONFIRMED → WAIT_MSS
→ MSS_CONFIRMED → WAIT_FVG → FVG_CONFIRMED → WAIT_RETRACE → STORY_COMPLETE

Nhánh: STORY_INVALIDATED, NY_BOTH_SIDES_TAKEN, NY_NO_REVERSAL, NY_NO_SWEEP, NO_STORY_FVG, NO_RETRACE
```

Kết quả London raid (case A–D) lưu riêng: `ASIA_HIGH_SWEPT / ASIA_LOW_SWEPT / ASIA_BOTH_SWEPT / ASIA_NOT_SWEPT`.
LondonStory: `LONDON_SWEPT_ASIA_HIGH / _LOW / _BOTH`, `LONDON_BROKE_ASIA_HIGH / _LOW`, `LONDON_INSIDE_ASIA`, `LONDON_NO_CLEAR_EVENT`.

Các state "chuyển tiếp" (`*_LOCKED`, `NY_LIQUIDITY_SWEPT`, `*_CONFIRMED`) được ghi đúng trên nến xảy ra sự kiện,
nến sau chuyển sang `WAIT_*` tương ứng.

## Quy tắc chính

**Không repaint.** Engine chỉ nhận **nến đã đóng**. Asia/London High-Low cập nhật động trong session, khóa khi session kết thúc.

**Sweep vs breakout** (mỗi level, cả High lẫn Low – đối xứng):

| Trạng thái | Điều kiện (ví dụ Asia High) |
|---|---|
| `ACTIVE` | chưa bị chạm quá `level + SweepBuffer` |
| `WICK SWEPT` | `High > level + buffer` nhưng `Close < level` |
| `TRADED THROUGH` | nến đóng trên level, chưa rõ reclaim hay acceptance |
| `RECLAIMED` | đã đóng trên level, sau đó một nến đóng trở lại dưới level |
| `BROKEN / ACCEPTED` | `InpAcceptBars` nến đóng liên tiếp phía trên level |

`SWEPT` = WICK SWEPT hoặc RECLAIMED; `BROKE` = ACCEPTED (hoặc vẫn TRADED THROUGH khi London kết thúc).
Mỗi lần level bị lấy được gắn session thực hiện (ASIA / PRE-LONDON / LONDON / PRE-NY / NY / POST-NY).

**Asia Range quality:** `AsiaRange / ATR(InpRangeAtrTf, InpRangeAtrPeriod)` của nến HTF đã đóng trước đó
→ `NARROW / NORMAL / WIDE` theo threshold tùy chỉnh. Chỉ dùng để phân nhóm thống kê, không suy luận hướng.

**NY targets** (xác định khi NY mở, chỉ các level còn nguyên): London H/L, Asia H/L, PDH/PDL (chưa bị lấy trong ngày),
swing high/low gần nhất đã xác nhận và chưa bị lấy. Panel ưu tiên hiển thị London H/L nhưng logic không ưu tiên cứng level nào.

**Reversal legs:** mỗi hướng có một leg riêng.
Sweep BSL → leg **bearish** chờ displacement giảm; sweep SSL → leg **bullish**.
Nếu cả hai bên bị lấy khi hai leg còn đang chờ → `BOTH SIDES LIQUIDITY TAKEN – WAIT FOR STRUCTURE`;
leg nào có **Displacement + MSS** trước thì xác định hướng câu chuyện.

- **Displacement:** nến ngược hướng sweep, `Body ≥ ATR × DisplacementATRFactor` và/hoặc
  `Body ≥ AverageBody × BodyMultiplier` (`InpDispMode`: ATR / BODY / BOTH / EITHER), trong `InpDispMaxBars` nến sau sweep.
  ATR và AverageBody lấy của các nến **trước** nến đang xét.
- **MSS:** swing (fractal `InpSwingStrength`) đã xác nhận gần nhất trước displacement; MSS khi **giá đóng cửa** vượt swing
  (không dùng wick), trong `InpMssMaxBars` nến.
- **Story FVG:** FVG 3 nến cùng hướng, nến giữa ≥ nến displacement (hoặc chỉ sau MSS nếu `InpFvgAfterMssOnly`).
  FVG khác được vẽ là **normal FVG** (mờ).
- **Retrace:** chạm proximal / CE / distal (`InpRetraceLevel`) sau khi Story FVG xác nhận → `FVG RETRACED`,
  `STORY CONDITIONS COMPLETE`. Retrace **không** phải lệnh vào.

**Failed story** (chống hindsight bias):

| Tình huống | Kết quả |
|---|---|
| Không có displacement kịp thời | `NO REVERSAL CONFIRMATION (NO DISPLACEMENT)` |
| Có displacement, không MSS / không có swing tham chiếu | `NO REVERSAL CONFIRMATION (NO MSS)` |
| Giá acceptance phía trên level vừa sweep | `NO REVERSAL CONFIRMATION (ACCEPTANCE BEYOND LEVEL)` |
| Đóng cửa vượt đỉnh sweep trước MSS | `NO REVERSAL CONFIRMATION (STRUCTURE CONTINUED)` |
| Sau MSS, đóng cửa vượt đỉnh/đáy sweep | `STORY INVALIDATED` |
| MSS nhưng không có FVG / FVG không retrace trước cutoff | `NO STORY FVG` / `NO RETRACE` |

**Model 1 / Model 2** chỉ là nhãn mô tả khi sequence thực tế khớp:
London sweep Asia Low → NY sweep London High → bearish MSS (Model 1) và đối xứng (Model 2).
Không có logic nào ép NY phải đi theo model.

**Silver Bullet** chỉ là tag (`SILVER BULLET CONDITIONS PRESENT` khi MSS hoặc Story FVG nằm trong window).
Logic không thay đổi, hiệu quả phải được backtest.

## Hiển thị

- Box Asia (kèm `NARROW/NORMAL/WIDE x.xx ATR`) và London (kèm London result).
- Level BSL/SSL kéo dài tới khi bị lấy: nét liền = ACTIVE, gạch = SWEPT/RECLAIMED, chấm = BROKEN/TRADED.
- Nhãn: `ASIA SSL SWEEP - LONDON`, `NY SWEEP LONDON BSL`, `Bearish Displacement`, `MSS ↓`, `STORY FVG`, `RETRACE`,
  `NO REVERSAL CONFIRMATION (...)`, `STORY INVALIDATED`.
- Story path (đường chấm): Asia → London sweep → London extreme → NY sweep → displacement → MSS → FVG → retrace.
- Panel timeline (mục 21 của spec) + khối thống kê.

### Nhãn rõ ràng, tránh chồng lên nhau

| Input | Mặc định | Ý nghĩa |
|---|---|---|
| `InpLabelMode` | `COMPACT` | `FULL`: mọi sự kiện có chữ. `COMPACT`: sự kiện sweep/reclaim/break của level chỉ còn chấm đánh dấu, trạng thái nằm trong nhãn của level (vd. `ASIA BSL 84567.12 [SWEPT LONDON]`), chữ ngắn (`DISP ↓`, `NO REVERSAL (NO MSS)`). `MINIMAL`: chỉ box, level Asia/London và chuỗi NY đã xác nhận. |
| `InpLabelDays` | `1` | Chỉ các ngày mới nhất có nhãn chữ; ngày cũ chỉ còn box, đường level và tên box. |
| `InpAvoidOverlap` | `true` | Sắp xếp nhãn theo pixel: nhãn ưu tiên cao (chuỗi NY → tên box → NY target → level → sự kiện phụ) đặt trước, nhãn va chạm được đẩy lên/xuống từng dòng; nhãn phụ không còn chỗ sẽ bị ẩn. Tự sắp xếp lại khi zoom / cuộn chart. |

Nhãn của level đặt ở **cuối đường** (nơi level bị lấy hoặc đang còn mở), tách khỏi tên box Asia/London ở đầu.

## Buffers (cho EA qua `iCustom`)

| # | Buffer | Ý nghĩa |
|---|---|---|
| 0 | DLS State | `ENUM_DLS_STATE` sau khi xử lý nến đóng đó |
| 1 | DLS Story Dir | -1 bearish / +1 bullish (sau MSS), 0 nếu chưa có |
| 2–3 | Asia High / Low | |
| 4–5 | London High / Low | |
| 6–7 | Story FVG Top / Bottom | |

Nến đang chạy luôn `EMPTY_VALUE`. Có thể dùng trực tiếp `CDlsEngine` trong EA (không phụ thuộc chart).

## Thống kê & kiểm chứng

Panel hiển thị A–L trên dữ liệu `InpLookbackDays`. CSV `MQL5/Files/NTA_DLS_<SYMBOL>_<TF>.csv` có một dòng cho mỗi ngày:
level, status, session đã lấy, LondonStory, các cờ funnel (sweep → displacement → MSS → FVG → retrace),
Silver Bullet tags, thời điểm từng bước, entry tham chiếu (mức retrace), MFE/MAE (giá và theo ATR, đo tới `InpEvalEnd`).

MFE/MAE: tính từ mức retrace; nến retrace chỉ tính phía bất lợi (High/Low) và close cho phía có lợi
vì không biết thứ tự giá trong nến.

```
python3 tools/dls_stats.py NTA_DLS_XAUUSD_M1.csv NTA_DLS_XAUUSD_M5.csv NTA_DLS_XAUUSD_M15.csv --by-class --csv summary.csv
```

| Mục | Ý nghĩa |
|---|---|
| A / B / C | London sweep Asia High / Low / cả hai |
| D | Sau khi London sweep một phía Asia, NY lấy London liquidity phía đối diện |
| E / F / G / H | NY sweep → displacement → MSS → FVG → retrace |
| I / J | MFE / MAE (đơn vị ATR) |
| K | So sánh theo symbol + timeframe (M1 / M5 / M15) |
| L | Trong / ngoài Silver Bullet window |

Không có giả định nào rằng sequence ICT/SMC có lợi thế thống kê – mục tiêu là **kiểm chứng bằng dữ liệu**.
