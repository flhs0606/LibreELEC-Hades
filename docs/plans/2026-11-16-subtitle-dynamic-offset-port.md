# F9 动态字幕偏移原生化移植 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 F9 动态字幕偏移功能以纯增量 patch 形式移植到 Hades 的 kodi 22.0rc2-Piers，产出 `packages/mediacenter/kodi/patches/1017-subtitles-dynamic-offset.patch`。

**Architecture:** 两层叠加——原生定位层（MANUAL/校准/posResInfo 机制）零改动，动态偏移作为渲染期纯增量层（`Render()` 平移 + 按键传输链）。播放中 vshift 动作（ACTION_SUBTITLE_VSHIFT_UP/DOWN）的 `CPlayerController::OnAction` 处理体是唯一被替换的代码。

**Tech Stack:** C++17（Kodi 22），std::atomic relaxed，Kodi settings 框架（settings.xml/SubtitlesSettings/strings.po），LibreELEC patch 体系。

**Spec:** `docs/specs/2026-11-16-f9-subtitle-dynamic-offset-port-design.md`（本计划从 spec 推导，执行者须同时读两者）

## Global Constraints

- 所有命令经 WSL：`wsl -d Ubuntu --cd <path> -- bash -c '<cmd>'`
- 所有代码注释用严谨的专业英语（AGENTS.md 规定）
- **禁止**运行任何构建/编译命令（`build_mt`/`unpack`/`make`），除非用户明确授权；本计划内验证全部用 tar + `patch -p1 --dry-run` 完成
- 唯一参照树：`/tmp/xbmc-22.0rc2-Piers`（stock tarball 全量解包）；F9 diff（`/tmp/f9_sub_offset.diff`、`/tmp/f9_player_headers.diff`、`/tmp/f9_player_bodies.diff`）仅作语义参考，**禁止机械套用**（F9 基于 Kodi 21，行号/上下文在 22 无效；定位一律用符号名 grep）
- 新字符串编号 **60500-60507**（39202-39209 已被 stock 22.0rc2 占用，禁用）
- patch 文件名：`1017-subtitles-dynamic-offset.patch`（4 位编号、无包名前缀，符合仓库惯例）
- 不触碰：keymaps、skin、GUIWindowSettingsScreenCalibration、GUIWindowFullScreen、RendererAML、CPUInfoLinux、`IVideoPlayer.h`（其中 `SetAllowPassthrough` 是 vsync 内容，不移植）
- 最终 patch 必须为 plain unified diff（`git diff` 输出，不带 mail 头）

## Review Focus（静态可查的五类易错点及对应检查）

1. **原生 MANUAL/posResInfo 机制被误删** — 暴力移植最大风险。检查（Task 6 Step 3）：`grep -c "Align::MANUAL" OverlayRenderer.cpp` pristine 与 patched 相等；patched `OverlayRenderer.cpp` 仍含 `case ObservableMessagePositionChanged:` 与 `POSRESINFO_SAVE_CHANGES`。
2. **`Render()` 是 const 成员，atomic 成员缺 `mutable` 导致编译错** — 检查（Task 3 Step 6）：`grep "mutable std::atomic<float> m_subtitleDynamicOffset" OverlayRenderer.h` 命中。
3. **`Notify()` 误删原生 PositionChanged 分支**（F9 删了，我们保留）。检查（Task 3 Step 6）：两个 case 分支都在。
4. **PlayerController 清理 m_movingSpeed 时漏删引用或误删别的用途** — 检查（Task 5 Step 5）：`grep -c m_movingSpeed PlayerController.{h,cpp}` 为 0 且 `MOVING_SPEED` include 已删。
5. **字符串/设置 ID 引用错位**（settings.xml 的 label/help 指错号）。检查（Task 2 Step 5）：settings.xml 中 4 个 setting 的 label/help 与 strings.po msgctxt 一一对应核对表。

---

### Task 1: 建立移植工作区（一次性）

**Files:**
- Create: `/tmp/kodi-sub-port/`（工作区，含 git 仓库）

**Interfaces:**
- Produces: pristine 基线 commit（后续所有 diff 的锚点，记下其 SHA）

- [ ] **Step 1: 解包 stock tarball 到工作区并初始化 git**

```bash
mkdir -p /tmp/kodi-sub-port && cd /tmp/kodi-sub-port
tar xzf /tmp/kodi22rc2.tar.gz          # 得到 xbmc-22.0rc2-Piers/
cd xbmc-22.0rc2-Piers
git init -q && git add -A && git -c user.email=port@local -c user.name=port commit -qm "pristine kodi 22.0rc2-Piers"
git rev-parse --short HEAD              # 记下 = $PRISTINE
```

Expected: commit 成功；`git status` 干净。

- [ ] **Step 2: 确认 F9 参考 diff 在位**

```bash
ls -l /tmp/f9_sub_offset.diff /tmp/f9_player_headers.diff /tmp/f9_player_bodies.diff
```

Expected: 三个文件都存在（只读参考，不进 git）。

---

### Task 2: 设置层（Settings.h / SubtitlesSettings / settings.xml / strings.po）

**Files:**
- Modify: `xbmc/settings/Settings.h`（`SETTING_SUBTITLES_MOVIE` 之后）
- Modify: `xbmc/settings/SubtitlesSettings.h`（`GetVerticalMarginPerc()` 声明之后）
- Modify: `xbmc/settings/SubtitlesSettings.cpp`（ctor 初始化列表、`OnSettingChanged`、`GetVerticalMarginPerc` 实现之后）
- Modify: `system/settings/settings.xml`（`subtitles.align` 块之后、`subtitles.fontname` 之前）
- Modify: `addons/resource.language.en_gb/resources/strings.po`（文件中 39000+ 段落之后、`#40000` 之前的任意稳定位置，按 msgctxt 号排序插入）

**Interfaces:**
- Produces（后续任务依赖的精确签名，供 `CServiceBroker::GetSettingsComponent()->GetSubtitlesSettings()` 调用）:
  - `bool IsLocalMovementEnabled() const;`
  - `float GetPositionPercentage() const;`
  - `bool IsRememberOffsetEnabled() const;`
  - `float GetRememberedOffset() const;`
  - `void SetRememberedOffset(float value) const;`
  - 常量：`CSettings::SETTING_SUBTITLES_LOCALMOVEMENT` / `_POSITIONPERCENTAGE` / `_REMEMBEROFFSET` / `_SUBTITLEOFFSET`（值 `subtitles.localmovement` / `subtitles.positionpercentage` / `subtitles.rememberoffset` / `subtitles.subtitleoffset`）

- [ ] **Step 1: Settings.h 加 4 个常量**

在 `static constexpr auto SETTING_SUBTITLES_MOVIE = "subtitles.movie";` 之后加四个同式常量（值见 Interfaces）。

- [ ] **Step 2: SubtitlesSettings.h/.cpp 加访问器与注册**

- .h：5 个方法声明（Interfaces 签名），各带 F9 风格英文 doc comment（`\brief` 起头，注明单位/范围）。
- .cpp ctor：初始化列表把 4 个 `CSettings::SETTING_SUBTITLES_*` 追加到现有 setting 注册表。
- .cpp `OnSettingChanged`：新增分支——setting id 为 `SETTING_SUBTITLES_REMEMBEROFFSET` 且 `GetBool` 为 false 时，`m_settings->SetNumber(SETTING_SUBTITLES_SUBTITLEOFFSET, 0.0)`，附注释（F9 原注释语义：防止 guisettings 残留旧值在重开开关后复活）。
- .cpp 5 个 getter/setter 实现：直接透传 `m_settings->GetBool/GetInt/GetNumber/SetNumber`（float/double 显式转换）。

- [ ] **Step 3: settings.xml 插 4 个 setting（spec 固定值，逐字使用）**

锚点：`<setting id="subtitles.fontname"` 之前插入。结构与依赖关系照抄 F9（见 `/tmp/f9_sub_offset.diff` 第 316-355 行），仅字符串号换成下表映射：

| setting id | type | label | help | default | 约束 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| subtitles.localmovement | boolean | 60500 | 60501 | true | toggle |
| subtitles.positionpercentage | integer | 60502 | 60503 | 80 | 10-90 step 1，parent=localmovement，visible 依赖，slider percentage `{:d} %` |
| subtitles.rememberoffset | boolean | 60504 | 60505 | false | toggle |
| subtitles.subtitleoffset | number | 60506 | 60507 | 0.0 | -100.0..100.0 step 0.5，parent=rememberoffset，visible 依赖，slider `{:+.1f} %` |

所有 `<level>2</level>`。

- [ ] **Step 4: strings.po 加 8 条（编号映射固定）**

msgctxt 映射与 msgid（逐字取自 F9 diff `/tmp/f9_sub_offset.diff` 第 22-68 行，仅换号）：

| msgctxt | msgid |
| :--- | :--- |
| 60500 | Enable local subtitle movement |
| 60501 | When enabled, only subtitles in the lower portion of the screen will be moved. When disabled, all subtitles on the screen will be moved together. |
| 60502 | Subtitle position from top |
| 60503 | Defines the threshold percentage from the top of screen below which subtitles are affected by local movement. |
| 60504 | Remember subtitle offset |
| 60505 | When enabled, the position of subtitles moved during playback is saved and restored on next playback. |
| 60506 | Subtitle offset (remembered) |
| 60507 | Offset from default position, in percentage of screen height. Negative moves up, positive moves down. |

PO 条目格式：`#. <F9 原参考注释语义>` + `#: system/settings/settings.xml` + `msgctxt "#605xx"` + `msgid "..."` + `msgstr ""` + 空行。

- [ ] **Step 5: 静态验证 + 提交**

```bash
cd /tmp/kodi-sub-port/xbmc-22.0rc2-Piers
grep -cE 'msgctxt "#6050[0-7]"' addons/resource.language.en_gb/resources/strings.po   # 期望 8
grep -c '60500\|60502\|60504\|60506' system/settings/settings.xml                      # 期望 4
python3 -c "import xml.dom.minidom;xml.dom.minidom.parse('system/settings/settings.xml')"  # XML 合法
git add -A && git -c user.email=port@local -c user.name=port commit -qm "settings: add dynamic subtitle offset settings (60500-60507)"
```

---

### Task 3: OverlayRenderer 渲染核心（纯增量）

**Files:**
- Modify: `xbmc/cores/VideoPlayer/VideoRenderers/OverlayRenderer.h`
- Modify: `xbmc/cores/VideoPlayer/VideoRenderers/OverlayRenderer.cpp`

**Interfaces:**
- Consumes: Task 2 的 5 个访问器
- Produces（Task 4/5 依赖）:
  - `void SetDynamicSubtitleOffset(const float value);`（CRenderer protected）
  - `float AdjustDynamicSubtitleOffset(float delta);`（同上；clamp [-100,100] 并返回新值）
  - `COverlay` 公有成员 `bool m_isDynamic{false};`

- [ ] **Step 1: OverlayRenderer.h — COverlay 增成员**

`bool m_pgsSubtitle{false};` 之后加：
```cpp
bool m_isDynamic{false}; // true if subtitle can be moved up/down (dynamic), false if fixed (static)
```

- [ ] **Step 2: OverlayRenderer.h — CRenderer 增声明与成员**

- `SetSubtitleVerticalPosition` 声明之后加两个方法声明（Interfaces 签名，F9 风格 doc comment：单位=屏幕高度百分比、方向=负上正下）。
- 成员区 `int m_subtitlePosition{0};` 附近加：
```cpp
mutable std::atomic<float> m_subtitleDynamicOffset{0.0f}; // dynamic offset, % of view height
```
（`<atomic>` 已因 `m_isSettingsChanged` 可用；`mutable` 必需——`Render()` 是 const。）

- [ ] **Step 3: OverlayRenderer.cpp — Reset() 注入记忆偏移**

定位 `void CRenderer::Reset()`（grep 锚点 `m_subtitlePosition = 0;`）。**保留**原生两行不动，其后追加：
```cpp
// Inject the remembered offset at playback (re)start: Reset() runs after
// Configure() and is the last write before the next render.
const auto subSettings{CServiceBroker::GetSettingsComponent()->GetSubtitlesSettings()};
m_subtitleDynamicOffset.store(subSettings->IsRememberOffsetEnabled()
                                  ? subSettings->GetRememberedOffset()
                                  : 0.0f,
                              std::memory_order_relaxed);
```

- [ ] **Step 4: OverlayRenderer.cpp — Render() 分类与平移**

定位 `void CRenderer::Render(COverlay* o) const` 中 `state.x += GetStereoscopicDepth(...)` 行，其后插入（语义逐字取自 F9，注意 22 上下文可能形如 `GetStereoscopicDepth(o->m_pgsSubtitle, o->m_3dSubtitleDepth)`）：
```cpp
// Classify non-ASS subtitles (image/SPU) by final screen y position.
// ASS subtitles are classified in ConvertLibass from rOpts.position.
const auto subSettings{CServiceBroker::GetSettingsComponent()->GetSubtitlesSettings()};
const bool localMovement = subSettings->IsLocalMovementEnabled();
const float posPct = subSettings->GetPositionPercentage();

if (o->m_align != COverlay::ALIGN_SCREEN)
{
  const float dynamicThreshold = m_rv.y1 + m_rv.Height() * (posPct / 100.0f);
  o->m_isDynamic = (state.y >= dynamicThreshold);
}

// Apply the dynamic offset (% of view height). With local movement only
// subtitles classified as dynamic are moved, otherwise all move together.
if (!localMovement || o->m_isDynamic)
  state.y += m_rv.Height() * m_subtitleDynamicOffset.load(std::memory_order_relaxed) / 100.0f;
```

- [ ] **Step 5: OverlayRenderer.cpp — ConvertLibass 分类 + Notify 增量**

- `COverlay::Create(images, ...)` 结果赋给 overlay 之后、进 texture cache 之前加：
```cpp
// Classify ASS/libass subtitles by line position (0 = bottom, 100 = top).
overlay->m_isDynamic = (rOpts.position < 20.0);
```
- `Notify()` 的 `case ObservableMessageSettingsChanged:` 分支内（`m_isSettingsChanged = true;` 之后）追加：
```cpp
// Remember-offset disabled: snap the atomic to 0 so the next render reflects it.
const auto subSettings{CServiceBroker::GetSettingsComponent()->GetSubtitlesSettings()};
if (!subSettings->IsRememberOffsetEnabled())
  m_subtitleDynamicOffset.store(0.0f, std::memory_order_relaxed);
```
**禁改**：`case ObservableMessagePositionChanged:` 分支原样保留；MANUAL/posResInfo/`ResetSubtitlePosition`/`SetSubtitleVerticalPosition` 原样保留。若 `#include "settings/SubtitlesSettings.h"` 缺失则补（grep 先查）。

- [ ] **Step 6: 静态验证 + 提交**

```bash
grep -c "m_isDynamic" xbmc/cores/VideoPlayer/VideoRenderers/OverlayRenderer.{h,cpp}   # h=1, cpp=4
grep -c "mutable std::atomic<float> m_subtitleDynamicOffset" .../OverlayRenderer.h     # 1
grep -c "case ObservableMessagePositionChanged:" .../OverlayRenderer.cpp               # 1（仍在）
grep -c "Align::MANUAL" .../OverlayRenderer.cpp                                        # 与 pristine 相等
git add -A && git ... commit -qm "OverlayRenderer: render-time dynamic subtitle offset (additive)"
```

---

### Task 4: 播放器传输链（IPlayer → ApplicationPlayer → VideoPlayer → RenderManager）

**Files:**
- Modify: `xbmc/cores/IPlayer.h`（锚点 `virtual void SetSubtitleVerticalPosition(int value, bool save) {}` 之后）
- Modify: `xbmc/application/ApplicationPlayer.h`（锚点 `void SetSubtitleVerticalPosition(const int value, bool save);` 之后）/ `.cpp`（锚点 `CApplicationPlayer::SetSubtitleVerticalPosition` 实现之后）
- Modify: `xbmc/cores/VideoPlayer/VideoPlayer.h`（锚点 `SetSubtitleVerticalPosition ... override;` 之后）/ `.cpp`（新实现在 `CVideoPlayer::SetSubtitleVerticalPosition` 实现之后）
- Modify: `xbmc/cores/VideoPlayer/VideoRenderers/RenderManager.h`（锚点 `void SetSubtitleVerticalPosition(...)` 声明之后）/ `.cpp`（锚点 `CRenderManager::SetSubtitleVerticalPosition` 实现之后）

**Interfaces:**
- Consumes: Task 3 的 `CRenderer::Set/AdjustDynamicSubtitleOffset`
- Produces（Task 5 依赖）: `appPlayer->AdjustDynamicSubtitleOffset(float delta) -> float`

- [ ] **Step 1: 各头文件加声明**（doc comment 取自 `/tmp/f9_player_headers.diff`，逐字）

- `IPlayer.h`：`virtual void SetDynamicSubtitleOffset(float value) {}` 与 `virtual float AdjustDynamicSubtitleOffset(float delta) { return 0.0f; }`（带 F9 的完整 doc comment，含 atomic read-modify-write 说明）。
- `ApplicationPlayer.h` / `VideoPlayer.h` / `RenderManager.h`：对应声明（ApplicationPlayer/RenderManager 非 virtual，VideoPlayer 带 `override`）。

- [ ] **Step 2: 各 cpp 加实现**（透传体逐字取自 `/tmp/f9_player_bodies.diff`）

- `ApplicationPlayer.cpp`：`GetInternal()` 空指针守护模式（Set 无返回；Adjust 无 player 时返回 0.0f）。
- `VideoPlayer.cpp`：转调 `m_renderManager` 同名方法。
- `RenderManager.cpp`：转调 `m_overlays` 同名方法。

- [ ] **Step 3: 静态验证 + 提交**

```bash
grep -rn "AdjustDynamicSubtitleOffset" xbmc/ | wc -l    # 期望 8（4 声明 + 4 实现/调用点）
git add -A && git ... commit -qm "player: transport chain for dynamic subtitle offset"
```

---

### Task 5: PlayerController 接管 vshift

**Files:**
- Modify: `xbmc/video/PlayerController.h`（删 `UTILS::MOVING_SPEED::CMovingSpeed m_movingSpeed;` 成员；加私有 `void PersistRememberedOffsetIfEnabled(float offset);`；ctor 改 `= default`）
- Modify: `xbmc/video/PlayerController.cpp`（ctor 清理、新私有方法、两个 vshift case 体替换）

**Interfaces:**
- Consumes: Task 2 `IsRememberOffsetEnabled/SetRememberedOffset`；Task 4 `appPlayer->AdjustDynamicSubtitleOffset`

- [ ] **Step 1: 清理 m_movingSpeed**

先 grep 确认 `m_movingSpeed` 在 22.0rc2 中只有 ctor 的 2 个 `AddEventConfig(ACTION_SUBTITLE_VSHIFT_*)`、两个 vshift case 内的 `GetUpdatedDistance` 与成员声明这些引用（若还有其他用途，停下来向用户报告）。确认后：ctor 体清空改 `= default`，删 `using namespace UTILS;`（仅当文件内无其他 `UTILS::` 引用）、删成员声明、删对应 include（`utils/MovingSpeed.h` 之类，grep 确认）。

- [ ] **Step 2: 加 PersistRememberedOffsetIfEnabled**（.h 私有声明 + .cpp 实现，逐字取自 F9）

```cpp
void CPlayerController::PersistRememberedOffsetIfEnabled(float offset)
{
  const auto subSettings{CServiceBroker::GetSettingsComponent()->GetSubtitlesSettings()};
  if (subSettings->IsRememberOffsetEnabled())
    subSettings->SetRememberedOffset(offset);
}
```

- [ ] **Step 3: 替换两个 vshift case 体**（F9 逐字，注意保留 case 外围结构与 `return true;`）

```cpp
case ACTION_SUBTITLE_VSHIFT_UP:
{
  const float next = appPlayer->AdjustDynamicSubtitleOffset(-0.5f);
  PersistRememberedOffsetIfEnabled(next);
  ShowSlider(action.GetID(), 277, next, -100.0f, 0.5f, 100.0f);
  return true;
}
```
（DOWN 同构，`+0.5f`。）**不动**：`m_sliderAction == ACTION_SUBTITLE_VSHIFT_*` 的滑块取消逻辑（~666 行）。

- [ ] **Step 4: 静态验证 + 提交**

```bash
grep -c "m_movingSpeed\|MOVING_SPEED" xbmc/video/PlayerController.{h,cpp}   # 0
grep -c "AdjustDynamicSubtitleOffset" xbmc/video/PlayerController.cpp        # 2
git add -A && git ... commit -qm "PlayerController: vshift drives dynamic subtitle offset"
```

---

### Task 6: 导出 patch、放置、应用验证

**Files:**
- Create: `packages/mediacenter/kodi/patches/1017-subtitles-dynamic-offset.patch`（仓库交付物）

**Interfaces:**
- Consumes: Task 1-5 的 git 历史（$PRISTINE..HEAD）

- [ ] **Step 1: 生成 plain unified diff**

```bash
cd /tmp/kodi-sub-port/xbmc-22.0rc2-Piers
git diff $PRISTINE HEAD > /tmp/1017-subtitles-dynamic-offset.patch
grep -c "^diff --git" /tmp/1017-subtitles-dynamic-offset.patch   # 期望 16 个文件
```

- [ ] **Step 2: 干净树应用验证（模拟 LE patch 流程）**

```bash
mkdir /tmp/kodi-verify && cd /tmp/kodi-verify && tar xzf /tmp/kodi22rc2.tar.gz
cd xbmc-22.0rc2-Piers && patch -p1 --dry-run < /tmp/1017-subtitles-dynamic-offset.patch
```
Expected: 16 个文件的 hunk 全部 `succeeded`，**无 fuzz、无 offset 警告**；随后去掉 `--dry-run` 实际应用成功。

- [ ] **Step 3: Review Focus 终检（对照本计划头部 5 项）**

```bash
grep -c "Align::MANUAL" xbmc/cores/VideoPlayer/VideoRenderers/OverlayRenderer.cpp          # == pristine 值
grep -c "POSRESINFO_SAVE_CHANGES\|case ObservableMessagePositionChanged:" 同文件             # 均在
grep -c "mutable std::atomic<float> m_subtitleDynamicOffset" .../OverlayRenderer.h          # 1
grep -cE 'msgctxt "#6050[0-7]"' addons/.../strings.po                                        # 8
```

- [ ] **Step 4: 放入仓库交付物**

```bash
cp /tmp/1017-subtitles-dynamic-offset.patch \
   /home/mephis/Project/LibreELEC-Hades/packages/mediacenter/kodi/patches/
```
（不 commit——AGENTS.md 禁止自主 git 操作；向用户报告并等待指示。）

- [ ] **Step 5: 报告 + 可选构建/上机验证清单（需用户授权/上机）**

按 AGENTS.md 规则停止并汇报：改动摘要、patch 统计、验证结果。授权后可跑：
`PROJECT=Generic ARCH=x86_64 ./scripts/build_mt kodi`（读 `${BUILD}/.threads/logs/` 日志）。
上机行为清单（以 spec §8 修订版为准）：ctrl+↑/↓ 位移+滑块显示百分比；局部移动阈值（顶部字幕不动）；记忆偏移跨播放保留；播放中关闭 remember 开关→立即归零一次、其他字幕设置变更不清零（修复波语义）；seek/章节跳转/切字幕轨→会话内偏移保持；播放中显示刷新率切换→remember 关归零、remember 开保持；校准窗口字幕条照常；align 选项含 Manual 照常；设置面板 4 个新项联动正确。
