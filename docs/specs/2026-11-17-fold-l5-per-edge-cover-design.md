# 折叠（pack fold）激活时 L5 cover 按边精确化 — 设计文档

日期: 2026-11-17（2026-11-18 按代码审查修正；同日实施并实机验证，见 §8）
状态: 已实施（补丁 `kodi-9999-zzzf-*`，9 文件，见 §7）并实机验证通过
影响面: kodi 补丁序列（`kodi-9999-zzzf-*`，见 §7）
关联: `kodi-9999-zzzc-*`（折叠/开关）、dvbridge `dvbridge_l5check` / cover 体系

## 1. 问题

DV RPU 的 L5 块（活动区偏移）随元数据发给显示设备；有东西画在黑边上时，
cover 机制把**被覆盖边**的 L5 摘除，防止电视 blank 掉绘制内容。现状有三种
cover 模式（[WinSystemGbmGLESContext.cpp:611](../../build.LibreELEC-Generic.x86_64-13.0-devel/build/kodi-22.0rc2-Piers/xbmc/windowing/gbm/WinSystemGbmGLESContext.cpp#L611)）:

| 模式 | 条件 | 行为 |
| :--- | :--- | :--- |
| `Cover::NONE` | 无 GUI 压画面 | L5 原样发送 |
| `Cover::MEASURE` | 等待式呈现 + 未折叠 | GPU 实测按边精确摘除 |
| `Cover::BARS` | 超前帧呈现，**或折叠激活** | **所有有黑边的边全摘** |

折叠（pack pass 直接混合 GUI）后 MEASURE 结构性不可能——GUI 混进打包 pass，
没有可测量的中间合成结果（[dvbridge_render.h:675](../../build.LibreELEC-Generic.x86_64-13.0-devel/build/kodi-22.0rc2-Piers/tools/dvbridge/dvbridge_render.h#L675)：
"its level 5 block is then made with every edge that has bars"）。

**后果**：字幕只压下黑边时，上黑边的 L5 也被无辜摘除。对按活动区联动控光的
显示器（FALD 分区黑边关闭类），上边分区不再关闭 → 黑位抬升。字幕静止的整个
期间该效应持续。功能无损（L5 摘除只丢元数据、不丢画面样本），纯外观级退化。

## 2. 现成的机器（本方案零新 GPU 语义的根据）

1. **GUI 占用瓦片掩码**（drawn-tiles 优化在用）：
   [DVTilesUpdate()](../../build.LibreELEC-Generic.x86_64-13.0-devel/build/kodi-22.0rc2-Piers/xbmc/windowing/gbm/WinSystemGbmGLESContext.cpp#L7518)
   轮询打包器 pass 7 对被告知的 GUI 纹理（即 GUI FBO）的 GPU 掩码——掩码对象
   是 GUI 本身、不是合成结果；无源打包器时由 guimask 路径对 GUI FBO 直接做，
   两者同入 `m_tilesRects`（≤24 个占用矩形，>24 矩形或覆盖率过半则退化为
   整幅），**按代数缓存**（`m_guiGen` 跳变才重算，GUI 静止期间零每帧开销）。
   两类掩码（`TILES_PACKER` / `TILES_GUI_DV`）坐标同为**窗口（=3840×2160
   传输）像素**。
2. **cover 核心 API 本来就收位掩码**:
   `dvbridge_candidate_cover(candidate, cover)` 参数即 1左/2右/4上/8下 的
   bit mask——只是 Kodi 层从未传过（只传三态模式）。
3. **边距 CPU 侧可得，但须取 active-area 边距（审查修正）**: 候选的
   active-area margins（`dvbridge_active_area()`，
   [dvbridge_core.c:247](../../build.LibreELEC-Generic.x86_64-13.0-devel/build/kodi-22.0rc2-Piers/tools/dvbridge/dvbridge_core.c#L247)），
   传输像素——即 `dvbridge_render_pack()` 自算 bars 位所用的同一来源
   （[dvbridge_render.c:3982](../../build.LibreELEC-Generic.x86_64-13.0-devel/build/kodi-22.0rc2-Piers/tools/dvbridge/dvbridge_render.c#L3982)）。
   原设想的 `PreparedPictureBars()` **不可用**: 它返回图像样本空间的 bars
   （margins 按 dest 矩形缩放），与 `m_tilesRects` 的窗口像素不同空间，非 1:1
   缩放时相差数倍，直接求交会错位。为 Kodi 层加 ~3 行 `PreparedActiveArea()`
   直通即可。
4. **PQ 位图字幕的绘制矩形（实机勘误后新增的第二掩码来源）**: PGS 等
   `m_isHDROverlay` 字幕经 `BeginDVBridgeHDROverlays()` 直接画进 PQ 画面
   （视频后、GUI 前），**不经过 GUI FBO**——任何 GUI 瓦片掩码都看不到它。
   其实际绘制矩形 CPU 侧精确可知（`RenderHDROverlays()` 各 item 的
   `state.x/y/width/height`，窗口坐标、y 向下顶部原点，与边距同向），
   取联合矩形即为逐帧精确、零 GPU 开销的掩码来源。

## 3. 设计

**规则一句话：两路掩码（GUI 占用矩形 ∪ PQ 字幕矩形）按边 OR；GUI 越过画面
而其矩形不可信时整帧回退 BARS。**

```
对每条有黑边的边 (L/R/T/B):
  GUI 占用表有效 (m_tilesUse && m_tilesGen == m_guiGen && m_tilesRects 非空 &&
    m_tilesKind 为 TILES_PACKER 或 TILES_GUI_DV) 且 active-area 边距可得
    → 任一占用矩形伸进该边黑边带（GL 左下原点, 窗口像素, 整数精确比较）
      → 摘该边 L5
  本帧有 PQ 字幕画进画面 (DVHDROverlayDrawn 矩形非空, y 向下顶部原点)
    → 矩形伸进该边黑边带 → 摘该边（与上 OR）
  GUI 越过画面 (m_dvGuiOver: in-place / pack fold / dvComposite) 而占用表无效
    → 16（全摘 = 现状 BARS 行为）
  两路都无 → 0（四边保留）
```

判定基准是**占用**（occupancy: GUI FBO 里现存内容的范围），不是**脏区**
（dirty: 本帧重绘范围）。这是正确性关键：静止字幕不再产生脏区，但仍在 FBO
里、仍会被 pack 混合输出——若按脏区判定，静止字幕所在边会被判为无绘制而
恢复 L5，被电视 blank 掉，问题以更隐蔽的形式回归。

## 4. 时序安全性

串行守卫（`m_tilesGen == m_guiGen`）天然给出正确的不对称时序：

| 事件 | 序列 | 安全性 |
| :--- | :--- | :--- |
| 字幕出现 | GUI 重绘 → 代数跳变 → 掩码立即失效 → **当帧 BARS 全摘** | 无"新字幕首帧被 blank"窗口 |
| 字幕静止 | 掩码有效缓存 → 按边精确（未覆盖边保留 L5） | 修复生效的主场景，零每帧开销 |
| 字幕消失 | 代数跳变 → BARS 过渡 1-2 帧（异步掩码轮询落地）→ 按边恢复 | 恢复延迟只影响外观；现状即为 BARS/NONE 即时切换，不会更差（代码中不存在 cover 滞回机制） |

**PQ 位图字幕（画进画面路径）无上述窗口**：其矩形是 CPU 侧逐帧精确值，不缓存、
无代数——出现首帧即精确，消失当帧即恢复；安全兜底由"矩形空 → 该路不参与"
与 `m_dvGuiOver` 的 16 回退保证。

**不变量保持**：掩码只会**恢复**可证明无绘制边的 L5；任何不确定性退回全摘。
"绝不 blank 绘制内容"（cover 的存在理由）原封不动——本方案是该不变量约束下
的最大精度。

## 5. 改动清单（预计 ~40 行）

| 触点 | 改动 |
| :--- | :--- |
| `tools/dvbridge/dvbridge_render.h/.c` | +1 个 `DVBRIDGE_COVER_GIVEN`: 调用方位掩码直通 `dvbridge_candidate_cover()`（~5 行） |
| `CDVBridgeGLES::Pack()` 签名 | 多带 4-bit 边位参数, 三态枚举扩为四态（~3 行） |
| `CDVBridgeGLES` | +`PreparedActiveArea()` 直通 `dvbridge_active_area()`（~3 行, 数据源见 §2.3） |
| `WinSystemGbmGLESContext.cpp` cover 决策点 (~L611) | 有效占用表时用 `m_tilesRects` 对 active-area 边距（同为窗口像素）求 4 个 bit 传 `GIVEN`; 无有效表 → 维持原判定 `ahead ? BARS : MEASURE`（~15 行） |
| `WinSystemGbmGLESContext.cpp` CompositeGui 折叠分支 | GuiPackFold（converted transport 的 pack fold，本机实况）与 GuiInPlace 分支都在 `HdrTilesUpdate()` 之前 `return`——在 GuiPackFold 分支 `return` 前补 `HdrTilesUpdate(true)` 请求 GUI 掩码；两分支与 dvComposite 处置 `m_dvGuiOver`，掩码不新鲜时 `DVCoverEdges()` 返回 16 兜底 |
| `OverlayRenderer.h/.cpp` | `RenderHDROverlays()` 返回所画字幕的联合矩形（窗口坐标、y 向下，`CRect::Union()`；空 = 没画） |
| `RenderManager.cpp` | Begin/End 之间把矩形交 `dvWindow->DVHDROverlayDrawn(rect)` |
| `WinSystemGbmGLESContext.h/.cpp` 状态与判定 | 成员 `m_dvGuiOver` / `m_dvOverlayDrawn` / `m_dvOverlayRect`（与 `m_dvDrawnOver` 同生命周期，4 处复位点对齐）；`DVHDROverlayDrawn()` 暂存矩形；`DVCoverEdges()` 重写为两路联合判定 |

**受益面 = 全部 BARS 场景, 与折叠开关无关**。BARS 有两个触发器: 折叠激活
（结构性不可测）与超前帧呈现（无等待时机, 由 GPU 负载决定, 开关关闭的重负载
片源同样落入）。位掩码是 CPU 侧按代数缓存的数据, 不需要等待 GPU, 故对两者
及源传输 in-place 路径一律可用; MEASURE（未折叠 + 等待式, 24Hz 轻载）本就
精确, 不受影响。

无新设置项: 瓦片功能既有的 `dvdrawntiles` advancedsettings 开关即天然
kill-switch（关瓦片 → 无掩码 → 恒 BARS = 现状行为）。`dvguiscissor` 是
scissor 用途的门控, cover 用途的请求与它解耦后不再构成本功能的第二开关。

**GPU 代价: 零新增**。GUI 掩码按代数缓存，唯一开销是 GUI 每次重绘后一次掩码
回读，drawn-tiles 优化本来就在做；字幕矩形是 CPU 侧现成值，无任何 GPU 开销。
实施实测的两点勘误（2026-11-18）:
1. 折叠的主形态是 **GuiPackFold（converted transport）**，不是源传输 in-place：
   `CompositeGui()` 两个折叠分支都在 `HdrTilesUpdate()` 之前 `return`，折叠帧
   从不请求掩码——须在 GuiPackFold 分支内补 `HdrTilesUpdate(true)`；
2. **PQ 位图字幕（PGS）根本不经过 GUI FBO**（画进 PQ 画面，§2.4）——GUI 掩码
   对主测试场景（PGS 字幕）不可见，没有第二来源（字幕矩形）修复不可能覆盖
   字幕场景；瓦片掩码的收益对象是真正经 GUI 的叠加（OSD、SRT/ASS）。

## 6. 能修与不能修

**能消除**: 未被绘制覆盖边的亮度变化（字幕压下边时上黑边的分区不再陪绑）；
L5 翻转次数减少（上边不再随字幕出现/消失翻转）；GUI 完全不触黑边时（屏幕
中央的 OSD 等）现状 BARS 会全摘四边, 修复后四边全保留。

**不能消除（结构性, 任何方案同此）**: 字幕实际所在边的 L5 摘除——保留 L5
则电视 blank 该带、字幕消失；摘除则该边"文字以外黑区"不再被 gate。"画面上
画了东西"与"向电视声明此边为黑边"互斥，cover 已选正确一侧（保内容舍外观）。
字幕文字自身的分区亮度反应是电视对"黑底亮字"**内容**的响应，与元数据无关。

**可见性边界**: 本修复只对按活动区联动控光的显示器（FALD 类）有可观察收益；
不联动 L5 的显示器上现状与修复后均无差异（已实测确认）。

## 7. 交付形态

独立补丁
`kodi-9999-zzzf-dvbridge-the-cover-of-the-level-5-block-by-the-edges-of-what-is-drawn-over-the-picture.patch`
（dvbridge + Kodi 层同补丁，9 文件），落 `projects/Generic/patches/kodi/x86/`，
位于 zzze 之后、**zzzg 之前**应用（zzzg 的决策块 hunk 依赖本补丁的行，以
fuzz 1 应用，确定性无害）。不重触 zzzc/zzzg（已出货补丁不做无谓 rebase）。
验证流程同仓库标准: `clean` + `unpack` 干净应用 + 9 文件与实测源码态字节一致
+ 实机下述协议对照。

## 8. 验证协议（实机）

前置: L5 片源（有黑边、RPU 带 L5）+ 字幕开（压下黑边）+ 24Hz 片源做
MEASURE 对照组（59.94 重负载即使未折叠也走 BARS，不可作对照）。

读数: `hades.dv.l5sent`（左/右/上/下 实发 L5）与 `hades.dv.l5origin`
（rpu / drawn / picture）。**勘误（2026-11-18 实测）**: 它们不是按名可直取的
info label——按名请求返回空。实际是 `PublishPlayerInfo()` 发布到 **Home 窗口
属性**，且**仅在播放器信息页可见时**（`WINDOW_DIALOG_PLAYER_PROCESS_INFO`
或 `WINDOW_DIALOG_HADES_PLAYER_INFO`，或 "Check this setup" 运行期间）才刷新。
正确读法: JSON-RPC `XBMC.GetInfoLabels` 用
`Window(Home).Property(hades.dv.l5sent)` 语法；信息页关闭后属性冻结在最后一次
发布的值（关闭瞬间的终值发布可捕获无遮挡状态）。注意 codecinfo 对话框自身会
盖住黑边、触发 cover 摘边，无遮挡读数以关页终值为准。

| 状态 | 预期 `l5sent` |
| :--- | :--- |
| 字幕关（对照组） | 影片完整边距（cover=NONE） |
| 折叠关 + 24Hz + 字幕（MEASURE） | 上边保留、下边 0（现状即精确, 回归基准） |
| 折叠开 + 字幕（修复前） | 上、下边均 0（BARS 全摘, 即本 bug） |
| **折叠关 + 59.94Hz 重负载 + 字幕（修复前）** | **上、下边均 0（超前呈现同样触发 BARS, 与开关无关）** |
| 折叠开 + 字幕（修复后） | **上边保留、下边 0**（与 MEASURE 等价） |
| 折叠关 + 59.94Hz + 字幕（修复后） | **上边保留、下边 0**（同上, 超前呈现场景一并修复） |
| 中央 OSD 不触黑边（修复后） | 四边全保留（修复前 BARS 为全 0, 一并修复） |
| 字幕出现瞬间（修复后） | GUI 叠加: 首帧全摘（BARS 回退）→ 1-2 帧内精确；PQ 字幕: 首帧即精确 |

**实测记录（2026-11-18，双子杀手 59.94p DV P7 MEL，PGS 中文字幕，LE@192.168.50.9）**:

- 修复前: 字幕帧 `0 / 0 / 0 / 0`（origin=drawn，BARS 全摘）；无字幕帧
  `0 / 0 / 42 / 42`（origin=rpu，RPU 原 L5 完整）
- 修复后: 字幕帧 **`0 / 0 / 42 / 0`**（下摘、上留 42，origin=drawn）；
  无字幕帧 `0 / 0 / 42 / 42` 不变
- 回归: 600 帧/10s 满速、0 underflow、0 丢帧、A/V −41.8ms 稳定；变3
  （23.976p FEL，MEASURE 基线）240 帧/10s、0 丢帧，不受影响
- 注: 该机 PGS 走画进画面路径（§2.4），上述字幕帧读数验证的是**字幕矩形
  来源**；瓦片掩码来源的实证需 OSD/SRT（真经 GUI）场景

外观级验证（需 FALD 类电视）: 字幕显示期间观察上黑边亮度, 修复后应与无字幕
时一致。
