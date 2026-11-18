# DV L5 三态设置（automatic / direct / left aside）— 设计与实施文档

日期: 2026-11-18
状态: 已实施——补丁 `projects/Generic/patches/kodi/x86/kodi-9999-zzzg-dvbridge-the-level-5-offsets-of-a-video-as-a-setting-automatic-direct-or-left-aside.patch`（宿主序列化器三态测试绿灯；clean+unpack 全序列重放干净应用；待用户下次构建做整包编译与实机验证 §7）
影响面: kodi 补丁序列（`kodi-9999-zzzg-*`，见 §6），dvbridge 序列化器 + Kodi 设置管道
关联: `kodi-9645-*`/`kodi-9646-*`（L5 自动纠错）、`kodi-9216-*`（cover 机制）、
`kodi-9999-zzzf-*`（L5 cover 按边精确化）、`dvbridge_metadata.h` 序列化体系

## 1. 问题

用户诉求：让 DV L5（活动区偏移）直通显示设备，播放器端不做处理。现状**没有任何
L5 设置项**（45 个 `videoscreen.hadesdv*` 设置枚举确认），唯一行为即 automatic：
读 RPU L5 → 两种读法（画面偏移 / 3840×2160 master 偏移）映射到输出栅格 →
播放器按映射结果 blank 传输黑边、重写 L5 发送、cover 摘除被绘制边、GPU 实测
自动纠错矛盾 L5。

**默认值确认：现状即 automatic（值 0），默认行为逐位不变。**

## 2. 三态语义（设计核心）

新设置 `videoscreen.hadesdvl5`（integer，默认 0，专家级 level 3，
parent 依赖 `videoscreen.hadesdvnative`）：

| | 0 automatic（默认） | 1 direct | 2 left aside |
| :-- | :-- | :-- | :-- |
| 发送的 L5 | 映射重算值（现状） | **RPU 原始 offset 逐字节** | 画面位置合成值 |
| `d->margins`（播放器 blank 依据） | L5 映射 margins | **画面位置**（不 blank 画面内容） | 画面位置 |
| cover/taken（字幕压黑边摘边） | 有 | **无**（原样即原样） | 有（对合成边） |
| l5check GPU 实测 | 有 | 跳过 | 跳过 |
| 9645/9646 自动纠错 | 有 | 跳过（错 L5 原样发出） | 强制忽略 |
| RPU 无 L5 块的视频 | made_area 合成（现状） | 同左（无源 L5 可直通） | 同左（本就等价） |

**关键杠杆**：`d->margins` 是播放器端一切 blank 行为的单点数据源（经
`candidate->state.margins` → `dvbridge_active_area()` 分发到 mask/pack 钩子、
提前写黑边、`active_rows`、`source_cover`）。direct 与 ignore 都把 margins 定为
画面位置后，**渲染代码零改动**，全部消费点自动失效。

ignore 复用 `dvbridge_dv_l5()` 现有 ignored 路径的形状，但**不写**
`d->l5_ignored` per-video 状态——切回 automatic 立即恢复干净，不残留决策。
direct 的差异在"发送值 ≠ margins"：现有代码 `v[]` 一身两职（发送值兼
margins），direct 分支必须拆开（见 §4 Task A）。

## 3. 现成的机器（零新 GPU 语义的根据）

1. **序列化 case 5**（`dvbridge_metadata.h:780-791`）：`dvbridge_dv_l5()` 填
   `v[4]` → `memcpy(d->margins, v)` → taken 边发 0。direct 分支在此切入。
2. **ignored 路径形状**（`dvbridge_metadata.h:397-403`）：margins 取画面位置、
   `reading.l5` 保留原始 offset、`reading.l5_ignored` 固定文案、`d->refused=NULL`。
   ignore 模式即以此提前返回。
3. **画面位置 margins**：`dvbridge_dv_margins(d, 0,0,0,0, v)`（made_area 同源，
   `dvbridge_metadata.h:548-566`）。注意它会覆写 `reading.l5` 为全零，direct 分支
   须在其**后**覆写回原始 offset。
4. **设置管道 trims 样板**（全链照抄）：settings.xml（`system/settings/settings.xml:4201`）
   → `Settings.h:519` 常量 → `DVEngineSettings.h` Read(:98)/引擎(:126)/Resolve(:168)
   → `WinSystemGbmGLESContext.cpp` `DVEngineRead()`(:6010，读 :6032，应用 :6067)
   → `CDVBridgeGLES::SendTrims()`（`DVBridgeGLES.cpp:1949`）→ renderer 创建点
   调用（:677）→ `dvbridge_render_send_trims()`（`dvbridge_render.c:3745`）→
   `dvbridge_set_trims()`（`dvbridge_core.c:68`）→ 序列化器读 `d->no_trims`(:755)。
   引擎设置在**原生输出启动时**读取（:5913 调用 `DVEngineRead()`），三态切换
   下次原生输出启动生效，与 trims 一致。
5. **notes 一次性日志机制**：`NOTE_*` 位（`dvbridge_render.c:29,38`）、
   take_notes（:805-809）、Kodi 侧日志（`DVBridgeGLES.cpp:1119-1125`）。
   direct 模式借同一机制每个视频记一次。
6. **l5check 门控点**：`CWinSystemGbmGLESContext::DVCheckL5()`
   （`WinSystemGbmGLESContext.cpp:6265`），非 automatic 时整体跳过。
7. **字符串空位**：core string 41890-41894（已验证未占用）；设置项插在
   `hadesdvnotrims`（settings.xml:4201）之后；integer 枚举样板抄 `hadesdvcm40`
   （:4232-4255，options + spinner）。
8. **补丁编号位**：`zzzc/zzze/zzzf` 之后 → `zzzg`。

## 4. 改动清单（Task 分解，行号为当前解包树）

### Task A — dvbridge 核心（`tools/dvbridge/`，净增约 35 行）

| 触点 | 改动 |
| :-- | :-- |
| `dvbridge_core.h:89` 旁 | `#define DVBRIDGE_L5_AUTO 0` / `DVBRIDGE_L5_DIRECT 1` / `DVBRIDGE_L5_IGNORE 2`（仿 `DVBRIDGE_CM40_*` 样式）；`void dvbridge_set_l5(struct dvbridge_context*, int mode);`（仿 :79 `dvbridge_set_trims` 声明） |
| `dvbridge_core.c:68` 旁 | setter 实现（仿 `dvbridge_set_trims`）：`context->state.l5_mode = mode;` |
| `dvbridge_metadata.h` `struct dvbridge_dv`(:155 区域) | + `int l5_mode;`（注释：DVBRIDGE_L5_*，videoscreen.hadesdvl5） |
| `dvbridge_metadata.h` `case 5:`(:780-791) | direct 分支（插在 `dvbridge_dv_l5()` 调用前）：`dvbridge_dv_margins(d,0,0,0,0,m)` 算画面位置 → `memcpy(d->margins, m)`；再 `v[0..3] = e->l5.*_offset`（发送值）；随后覆写 `reading.l5 = 原始 offset`、`as_given = {0}`、`l5_master = false`、`reading.l5_direct = true`；**跳过** taken 摘边与适配拒绝。保留结构性拒绝（两个 L5 块、L5 前无 L1 块） |
| `dvbridge_metadata.h` `dvbridge_dv_l5()`(:382) 顶部 | ignore 提前返回：整体复用 :397-403 形状，固定文案 `"the setting videoscreen.hadesdvl5 leaves the level 5 offsets aside"`；**不调** `dvbridge_dv_ignore_l5_of()` |
| `dvbridge_metadata.h` `dvbridge_dv_restart()`(:474-491) | 保存/恢复列表加 `l5_mode`（同 `no_trims` 待遇，设置驱动不随流重置） |
| `dvbridge_core.h` `struct dvbridge_reading` | + `bool l5_direct;`；`dvbridge_core.c` `dvbridge_candidate_reading()`(:70 区域) 拷贝之 |
| `dvbridge_render.h` notes(:56-65) | + `bool l5_direct;`；+ `void dvbridge_render_set_l5(struct dvbridge_renderer*, int);` |
| `dvbridge_render.c` | setter（仿 :3745-3748）；`NOTE_L5_DIRECT`（:38 `NOTE_L5_IGNORED=512` 旁取下一空闲位）；fresh 置位（:1069 旁照 `l5_ignored` 模式） |

### Task B — Kodi 层（净增约 55 行）

| 触点 | 改动 |
| :-- | :-- |
| `xbmc/settings/Settings.h:519` 旁 | `static constexpr auto SETTING_VIDEOSCREEN_HADESDVL5 = "videoscreen.hadesdvl5";` |
| `system/settings/settings.xml:4201` 块后 | integer 设置：label 41890 / help 41891，requirement `HAVE_GBM`+`HAS_GLES`，deps visible `supportsdv` / enable `hadesdvnative=true`，level 3，default 0，options `41892→0 / 41893→1 / 41894→2`，control spinner string（结构照抄 `hadesdvcm40` :4232-4255） |
| `xbmc/windowing/gbm/DVEngineSettings.h` | Read 结构 + `int l5 = 0;`（:98 旁，注释注明 videoscreen.hadesdvl5）；引擎结构 + `int l5 = 0;`（:126 旁）；Resolve + `s.l5 = read.l5;`（:168 旁） |
| `WinSystemGbmGLESContext.cpp` `DVEngineRead()` | `read.l5 = integer(CSettings::SETTING_VIDEOSCREEN_HADESDVL5);`（:6032 旁，lambda 见 :6019）；应用 `m_dvBridge->UseL5Mode(m_dvEngine.l5);`（:6067 `SendTrims` 旁） |
| `WinSystemGbmGLESContext.cpp` `DVCheckL5()`(:6265) | in-flight collect（:6269-6272）之后、`l5check_video`(:6280) 之前：`if (m_dvEngine.l5 != DVBRIDGE_L5_AUTO) return;` + 注释 |
| `WinSystemGbmGLESContext.cpp` cover 决策(:610-631) | 非 automatic 时 `cover` 短路为 `NONE`（`m_dvEngine.l5 != DVBRIDGE_L5_AUTO` 时跳过 :614-631 的 ahead/MEASURE/BARS/GIVEN 决策与 `PreparedActiveArea()`/`DVCoverEdges()` 计算——direct 下序列化器本就丢弃 cover 位，此为省每帧空转；ignore 下 margins=画面位置、黑边带为空，决策亦必得 0 边，短路只是省计算）。ignore 模式无 per-edge 特判需求，自洽 |
| `DVBridgeGLES.h/.cpp` | `void UseL5Mode(int mode);` + `int m_l5ModeWanted = 0;`（实现仿 `SendTrims` :1949-1953）；renderer 创建点 `dvbridge_render_set_l5(m_renderer, m_l5ModeWanted);`（:677 旁）；notes 日志加 `l5_direct` 分支（:1119 旁）：`"DVBridge: the level 5 offsets of this video ({} {} {} {}) are sent as the RPU gives them (videoscreen.hadesdvl5)"` |
| `addons/resource.language.en_gb/resources/strings.po` | 5 条：41890 label / 41891 help / 41892-41894 选项（文案见 §7 附） |

### Task C — 验证与导出

1. 宿主 scratch 测试（`/tmp/opencode/`，不进补丁，仿 9645 的 `l5_test.c` 做法）：
   含 `dvbridge_metadata.h` 的小程序，断言三态：automatic 下输出字节与改动前
   完全一致（回归基准）；direct 下发送块 = 原始 offset 且 `margins` = 画面位置；
   ignore 下 `margins` = 画面位置且 `reading.l5_ignored` 为固定文案、
   `d->l5_ignored` 状态未置位。头文件取 toolchain
   （`build.../toolchain/include`）或系统 ffmpeg-dev；宿主不可编译时降级为
   unpack 干净应用 + 代码走查，运行验证移交实机（§7）。
2. 补丁导出：按 AGENTS.md 工作流（clean kodi → unpack → **在 kodi 树内
   `git init` + 提交原始树** → 实施 Task A/B → squash 为单提交），
   `git format-patch` 落
   `projects/Generic/patches/kodi/x86/kodi-9999-zzzg-dvbridge-the-level-5-offsets-as-a-setting-automatic-direct-or-left-aside.patch`，
   subject：`dvbridge: the level 5 offsets of a video as a setting (automatic, direct, or left aside)`。
3. `PROJECT=Generic ARCH=x86_64 ./scripts/clean kodi && ./scripts/unpack kodi`
   验证干净应用（构建类命令，执行时需明确放行）。

## 5. 语义边界（预期退化，写进设置 help 与提交说明）

- **direct 的几何错位是本质的**：L5 定义即最终 HDMI 栅格像素。非 4K 源 1:1
  全屏直映（1080p 源、缩放、zoom、校准偏移）时原始 offset 指向错误行，
  显示器按错行遮蔽。direct 只能定位为专家选项："信任显示设备"。
- direct 下字幕画进黑边不再摘边（taken 关闭），显示器会 mask 掉字幕。
- direct 下 9645/9646 自动纠错失效：open matte/错 RPU 的"丢行"按设计回归。
- direct 传输在活动区外不再保证黑（CCM 001 认证行为的偏离，显示器容错自担）。
- ignore 下画面自带黑边不再 blank（与"无 L5 视频"一致；FALD 类控光可见差异，
  与 zzzf 文档 §6 同类外观级差异）。
- 三态对 HDR10/HDR10+/HLG/vivid 转制 DV 路径无影响（无源 RPU L5，
  made_area 照旧）。

### 与既有设置的交互（核查结论：无冲突）

| 既有项 | 交互 | 结论 |
| :-- | :-- | :-- |
| `hadesdvaheadmode`（超前帧 → cover BARS） | direct/ignore 下 cover 短路 NONE，ahead 只影响绘制路径 | 无冲突 |
| `hadesdvguipackfold`（折叠 → cover BARS/GIVEN） | 同上；折叠照常工作，仅不再影响 L5 | 无冲突 |
| adv `dvdrawntiles`/`dvguiscissor`（zzzf cover 精确化） | 同上，cover 体系整体旁路 | 无冲突 |
| 9645/9646 自动纠错 / l5check | automatic 下照常；direct 跳过、ignore 强制——三者互斥由模式本身保证 | 互补非冲突 |
| cover 摘边（9216/zzzf） | direct 发送值旁路 taken；ignore margins=画面位置使边带为空 | 无冲突，见 Task B 短路行 |
| `hadesdvnative` | 新设置 parent 依赖它；关闭时 L5 体系整体不生效（现状） | 一致 |
| 字幕位置类设置（marginvertical、zzze 动态偏移） | 只改变字幕是否落黑边；direct 下落黑边的字幕会被显示器 mask（§5 已列） | 已文档化 |

## 6. 交付形态

单补丁 `kodi-9999-zzzg-*`（dvbridge + Kodi 层同补丁），落
`projects/Generic/patches/kodi/x86/`，位于 zzzf 之后应用。不重触已出货补丁。

**Pre-flight 警告**：
1. kodi build 树**不是**独立 git 仓库（`git` 上溯到 LibreELEC 仓库）——
   导出补丁前必须在 kodi 树内 `git init`（AGENTS.md 工作流本就如此）。
2. LibreELEC 仓库当前有未跟踪文件：`zzzf` 补丁与两份 `docs/specs/` 文档——
   实施前先确认 zzzf 定稿状态并提交，避免与 zzzg 混淆。
3. `clean kodi` 会重建解包树，须在 zzzf 状态落定后进行。

## 7. 实机验证协议

读数沿用 zzzf 文档 §8 方法：JSON-RPC `XBMC.GetInfoLabels` 请求
`hades.dv.l5sent` / `hades.dv.l5origin`，配合 kodi.log 三态一次性日志。

| 场景 | automatic 预期 | direct 预期 | ignore 预期 |
| :-- | :-- | :-- | :-- |
| 4K L5 正确片源全屏（对照组） | l5sent=影片边距 | **同值**（几何恒等，正确性基准） | l5sent=0（画面满幅） |
| 1080p 片源（非 1:1） | 映射值（缩放后） | 原始 offset（≈2× 映射值，错位语义展示） | 0 |
| open matte 错 L5 片源 | 自动忽略 + "left aside" 日志 | 原样发送 + direct 日志（丢行回归属预期） | 忽略 + 固定文案日志 |
| 字幕压下黑边 | 下边摘除（l5origin=drawn） | 不摘（l5origin=rpu），字幕被显示器 mask | 合成边摘除 |
| 默认 0 回归 | 与改动前 l5sent 逐位一致（含 cover/l5check 全行为） | — | — |

### 附：strings.po 文案（en_GB）

- `#41890` label: **Dolby Vision level 5 offsets**
- `#41891` help: How the active area offsets of the video's metadata reach the
  display. Automatic reads them and describes the picture as it is placed on
  the screen: the player blanks the bars itself and takes the edges it draws
  over out of them (the default). Direct sends the offsets as the RPU gives
  them and blanks nothing: right where the screen shows the video pixel for
  pixel, wrong wherever it is scaled or zoomed, and subtitles drawn over the
  bars are masked by the display. Left aside sends the area of the picture's
  place, as a video without them: the bars of the picture are not blanked.
- `#41892`: Automatic (read and mapped)
- `#41893`: Direct (as the RPU gives them)
- `#41894`: Left aside (the picture's area)
