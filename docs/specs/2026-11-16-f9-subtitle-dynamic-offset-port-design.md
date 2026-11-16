# F9 动态字幕偏移 → LibreELEC-Hades 原生化移植方案

日期: 2026-11-16（同日修订：原生化重构；实施后修订：§6/§8 行为规格更正）
状态: 已实施。交付物 `packages/mediacenter/kodi/patches/1017-subtitles-dynamic-offset.patch`
（16 文件，329 插入 / 68 删除；干净树应用零 fuzz；SDD 全程审查通过）

## 1. 目标与背景

把 CoreELEC F9 分支的"动态字幕偏移"功能移植到本仓库（Generic/x86_64，
kodi `22.0rc2-Piers`），patch 落在 `packages/mediacenter/kodi/patches/`。

**移植原则（用户决策）**：尽量用 Hades 原生实现，不暴力移植——以
22.0rc2 原生结构为基座做增量集成，不照搬 F9 在 Kodi 21 上的破坏性重写
（F9 删了 ~290 行上游代码，含校准窗口手术与皮肤删件，本方案全部不做）。

## 2. 源 commit 解构

功能跨 2 个 commit（播放器接线混在 vsync commit 里）：

| Commit | 承载内容 |
| :--- | :--- |
| `b926b24814d` | 渲染/设置/UI 侧：OverlayRenderer、SubtitlesSettings、settings.xml、strings |
| `655950a0689`（父） | 播放器接线：IPlayer/ApplicationPlayer/VideoPlayer 新 API、PlayerController vshift 重写 |

**不移植**：RendererAML、soc_thermal、HDR Vivid、strings.po 无关 churn、
vsync/tempo 全部、GUIWindowFullScreen 方向键劫持（用户否决）、以及 F9 的
MANUAL 体系删除（原生化方案保留 MANUAL，见 §4）。

## 3. 核心设计：两层叠加，零破坏

字幕渲染流水线中，原生定位与动态偏移作用在不同阶段，天然可叠加：

```
原生层（保留不动）                      移植层（纯增量）
────────────────────────────          ────────────────────────────
校准条/MANUAL 基准位置                  渲染期百分比平移
resInfo.iSubtitles                     Render(COverlay*) 中
 → m_subtitlePosition                   state.y += 画面高 × offset%
 → libass rOpts.position                仅作用于 m_isDynamic 字幕
持久化: RESOLUTION_INFO 校准数据        持久化: subtitles.subtitleoffset
```

- 最终位置 = 基准位置（任意对齐模式，含 MANUAL）+ 动态偏移
- 两套持久化互不覆盖（校准数据按分辨率 vs 独立 setting 全局）
- MANUAL 基准仍由校准窗口 GUI 字幕条调整；vshift 动作语义整体接管为
  百分比偏移（原生素：vshift 原生仅 MANUAL/BOTTOM_OUTSIDE 有效且其余
  模式早退，接管后所有模式统一生效）

## 4. 键位链路（已核实 stock 22.0rc2，零 keymap 改动）

```
keymap 绑定串（如 keyboard.xml:448 的 "SubtitleShiftUp"，大小写不敏感）
  → CActionTranslator::TranslateString: ToLower → 动作表命中
    "subtitleshiftup" → ACTION_SUBTITLE_VSHIFT_UP (230)
    （ActionTranslator.cpp:104；动作表优先级高于 builtin，CamelCase
     写法也从 keymap 解析为同一动作）
  → CApplication 输入派发
  → CApplicationActionListeners（Application.cpp:815 注册 CPlayerController）
  → CPlayerController::OnAction()   ← 唯一改写点
```

- stock 默认键位即用（ctrl+↑/↓），patch 不碰 keymaps
- 遥控自绑推荐动作名 `subtitleshiftup`/`subtitledshiftdown`
  （注意无 "v"；与键盘路径完全一致）
- builtin `SubtitleShiftUp(save)` 仅被 skin onclick / JSON Exec 直接调用
  时可达（keymap 中被动作表遮蔽）；`save` 参数在新语义下无意义，
  持久化由 rememberoffset 设置接管
- 纯 `<up>`/`<down>` 已绑章节/大步进（keyboard.xml），不动

## 5. 文件级变更清单（1 个 patch，16 个文件 / 11 组，~250 行增量 / ~50 行替换）

`packages/mediacenter/kodi/patches/1017-subtitles-dynamic-offset.patch`

| # | 文件 | 改动 | 性质 |
| :--- | :--- | :--- | :--- |
| 1 | `xbmc/settings/Settings.h` | +4 个 SETTING_ 常量 | 增量 |
| 2 | `xbmc/settings/SubtitlesSettings.h/.cpp` | +5 访问器；注册 4 setting；rememberoffset 关闭时清零 subtitleoffset | 增量 |
| 3 | `system/settings/settings.xml` | subtitles.align 后插 4 个 setting（localmovement/positionpercentage/rememberoffset/subtitleoffset）；**不删任何选项** | 增量 |
| 4 | `strings.po` | 8 条字符串 **60500-60507**（39202-39209 已被 Kodi 22 占用；stock 最大号 40804，60xxx 空闲） | 增量 |
| 5 | `OverlayRenderer.h` | COverlay +`m_isDynamic`；CRenderer +`m_subtitleDynamicOffset`(atomic<float>)、+2 方法声明 | 增量 |
| 6 | `OverlayRenderer.cpp` | Render() 增分类+平移（~25 行）；ConvertLibass 尾部 +ASS 分类（rOpts.position<20）；Reset() +注入记忆偏移；Notify() SettingsChanged case +remember 关闭时归零。**MANUAL 分支/posResInfo 机制全部原样保留** | 增量 |
| 7 | `RenderManager.h/.cpp` | +2 透传 | 增量 |
| 8 | `xbmc/cores/IPlayer.h` | +2 virtual 空实现 | 增量 |
| 9 | `xbmc/application/ApplicationPlayer.h/.cpp` | +2 透传 | 增量 |
| 10 | `xbmc/cores/VideoPlayer/VideoPlayer.h/.cpp` | +2 override → m_renderManager | 增量 |
| 11 | `xbmc/video/PlayerController.h/.cpp` | 两个 vshift case 体替换为 AdjustDynamicSubtitleOffset(±0.5f)+持久化+ShowSlider(-100~100,0.5)；构造函数删 vshift 的 m_movingSpeed 配置；+PersistRememberedOffsetIfEnabled | **唯一替换点** |

**不触碰**：GUIWindowSettingsScreenCalibration、skin.estuary 校准 XML、
keymaps、GUIWindowFullScreen、RendererAML、CPUInfoLinux。

## 6. 功能行为规格

- 位移范围 ±100%（画面高度百分比），每键 0.5%，OSD 滑块实时显示
- 触发：播放中 ctrl+↑/↓（stock 默认键位）；所有对齐模式生效
- 局部移动（默认开）：仅移动屏幕顶部往下 positionpercentage%（默认 80%）
  以下的字幕；ASS 按 libass 行位置（<20）分类，图像/SPU 按最终屏幕 y 坐标分类
- 记住偏移（默认关）：开启后每次按键写入 guisettings，下次播放 Reset() 恢复；
  关闭开关时实时归零并清空存储值（仅开关关闭动作本身触发——其他字幕设置
  变更不影响会话内偏移；终审修复波语义，优于 F9 的"任意设置变更即清零"）
- 偏移生命周期（原生 Flush→Reset 行为，与 F9 一致，2026-11-16 核实调用链）：
  seek、章节跳转、音轨/字幕轨切换**不重置**（渲染器不 Flush）；
  换文件/下一集、播放中显示模式切换（OnLostDisplay）、停止再播会重新推导
  （remember 开=注入持久值，关=归零）
- 校准窗口字幕条与 MANUAL 选项保留：定基准位置，与偏移叠加共存

## 7. 风险与缓解

| 风险 | 缓解 |
| :--- | :--- |
| Render() 钩子点在 22.0rc2 的上下文与 F9 基座不同 | 以 /tmp/xbmc-22.0rc2-Piers 为唯一参照手工落点，F9 仅作语义参考 |
| vshift 语义替换影响依赖像素持久化的老用法（SubtitleShiftUp(save)） | 接受：新语义更通用；基准位置仍可经校准窗口持久化 |
| 无编译验证（未授权 build） | 静态验证 + 逐 hunk review；授权后 build_mt kodi |
| 记忆偏移与视频设置恢复的时序（Reset() 调用点） | Reset() 注入点沿用 F9 结论（Configure 后最后一次写） |

## 8. 验证计划

1. `./scripts/unpack kodi` + patch 干净应用（无 fuzz）
2. （需授权）`PROJECT=Generic ARCH=x86_64 ./scripts/build_mt kodi`
3. 上机清单：ctrl+↑/↓ 位移+滑块显示百分比；局部移动阈值生效（顶部字幕不动）；
   记住偏移跨播放保留；播放中关闭 remember 开关→立即归零一次，之后改字体等
   其他字幕设置→偏移保持；seek/章节跳转/切字幕轨→会话内偏移保持（remember
   关也保持）；播放中显示刷新率切换→remember 关归零、remember 开保持；
   校准窗口字幕条照常；align 选项含 Manual 照常；4 个新设置项联动正确
