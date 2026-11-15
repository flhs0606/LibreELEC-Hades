# LibreELEC-Hades: 逐帧动态色调映射与三档画质重构工程规范

> **文档标识**: SPEC-HADES-DTM-QP-V1.1  
> **状态**: 架构设计与代码变更草案 (Architecture & Code Diff Specification - Awaiting User Approval)  
> **适用平台**: Generic x86_64 (Intel N100 / Xe-LP / Iris Xe / dGPU / AMD / NVIDIA)  
> **代码基线**: LibreELEC-Hades (`kodi-22.0rc2-Piers`)  
> **取代关系**: 取代 SPEC-HADES-PROJ-DTM-V3.0（`design-projector-dynamic-tone-mapping.md`）；落地时拆分回退其补丁 `kodi-9999`（见第六章）

---

## 一、 战略目标与重构背景

### 1.1 现状痛点
1. **触发门槛环形互锁**：
   - 依赖电视 EDID（LG/索尼等直接走 Native DV 隧道抢占，旁路映射）；
   - 依赖 `winscreen.ishdrdisplay`（关闭 HDR 后导致映射目标计算失败）；
   - 依赖播放器 OSD 内部的 `tonemapmethod`（默认 `0: Off` 导致 DVBridge 静默罢工并回退至硬截断 Shader）；
   - 依赖底层转换总闸 `videoscreen.hadesdvashdr10`。
2. **设置界面零碎晦涩**：
   - Group 6, 7, 8, 9 堆叠了大量底层变量（数字待盘点），用户心智负担极重。
3. **低算力设备（N100 等）算力过载**：
   - 开启重构模式后，默认的 ETSI GS CCM 001 浮点多项式算法占用大量着色器时间，加剧 4K FEL 场景的单帧渲染超时（"83ms"、"着色器开销降低 40%" 等数字均为待实测项，实施章验收时定量）。

### 1.2 重构原则：双域解耦（Dual-Domain Decoupling）
* **【逐帧动态映射】域**：专职控制"**输出目标与色彩映射**"（主开关、目标白点/峰值、Gamma、色域、曲线、对比度恢复）。开启后无视一切前置条件强制接管。
* **【画质设置】域**：专职控制"**GPU 算力分配与渲染引擎精度**"（着色器算法、色域网格精度、掉帧步进防御）。独立于动态映射，在全场景下守护整机的流畅度与画质上限。
* **Profile 7 FEL 分档承载**：Native DV 输出路径的 FEL 重建全档位恒开（不受任何设置影响）；`videoscreen.hadesdvashdr10fel` 仅作用于 DV→HDR10/SDR **转换路径**——标准档维持上游默认 `false`，高/极高画质档设 `true`（HDR10 电视亦享 12-bit FEL 重构）。N100 的算力压力由步进体系兜底（实测：FEL 干净帧 31.4ms，在前瞻预算内）。

---

## 二、 交互层重组 (UI & Settings Structure)

在 `设置 -> 系统 -> 显示` (System -> Display) 下设立两个独立分支：

### 2.1 【逐帧动态映射】分支
```text
[ 逐帧动态映射 ]  (互斥：两分支同一时刻至多开启一个)
  ├── ⚪ 逐帧动态映射到 SDR (videoscreen.hadesdtmsdr)
  │    ├── 目标亮度 (Target White)：500 nits (100 - 1500 nits)
  │    ├── 目标 Gamma：1.8 (1.8 - 2.4)
  │    ├── 目标色域 (Target Gamut)：DCI-P3 (D65) / BT.2020 / BT.709
  │    ├── 映射曲线 (Tone Curve)：BT.2390 / Spline / BT.2390 libplacebo knee
  │    └── 动态对比度恢复 (Contrast Recovery)：20% (0% - 50%)
  │
  └── ⚪ 逐帧动态映射到 HDR (videoscreen.hadesdtmhdr)
       ├── 目标显示峰值 (Target Peak)：800 nits (200 - 4000 nits)
       ├── 目标色域 (Target Gamut)：DCI-P3 (D65) / BT.2020
       ├── 映射曲线 (Tone Curve)：BT.2390 / Spline / BT.2390 libplacebo knee
       └── 动态对比度恢复 (Contrast Recovery)：20% (0% - 50%)
```

**互斥与优先级规则**：
* UI 层用 settings.xml 依赖实现互斥（开启其一自动置零另一）。
* 读取层防御：若 `guisettings.xml` 被手改导致两者同时为真，仲裁取 `hadesdtmsdr` 优先并记录 `CLog::Log(LOGWARNING, ...)`。

**默认值说明**：上表默认值（500 nits / Gamma 1.8 / 20%）为面向高亮电视的初稿值，与被取代的 v3.0 投影仪预设（100 nits / Gamma 2.4 / 0%）不同，实施后需在投影仪与电视两类设备上实测校准后再定稿。

### 2.2 【画质设置】分支
```text
[ 画质设置 ] (videoscreen.hadesqualitypreset)
  └── 🔘 画质模式：
       ├── ⚪ 0: 标准 (Standard)    [推荐 Intel N100 / 入门核显]  (libplacebo 合成 + 步进锁 L1，实测含 PGS 字幕满帧——V1.2)
       ├── 🔘 1: 高画质 (High)     [推荐 Iris Xe / Radeon 780M]  (+ FEL 转换路径重构 + 精细色域 LUT)
       └── ⚪ 2: 极高画质 (Ultra)   [推荐 独立显卡]              (高画质 + 步进锁 NEVER 全精度)
```

---

## 三、 三档画质预设与底层映射矩阵

### 3.1 矩阵

| 底层控制项 ID | 设置项中文名 | 🟢 标准 (Standard - N100) | 🔵 高画质 (High - Iris Xe/780M) | 🟣 极高画质 (Ultra - 独显) | 设计意图 |
|---|---|---|---|---|---|
| `videoscreen.hadesdvashdr10fel` | P7 FEL 残差重构（转换路径） | **`false`**（上游默认） | **`true`** | **`true`** | 标准档对齐上游；高档位在 HDR10 电视上享受满血 12-bit FEL 重构。Native DV 路径全档恒开，不受此设置影响。 |
| `videoscreen.hadesdvcomposer` | 重塑计算算法引擎 | **`1: LIBPLACEBO`**（V1.2） | **`0: SPECIFICATION`** | **`0: SPECIFICATION`** | 高/极高维持 CCM（干净帧更快更合规）；标准档改 libplacebo——覆盖帧（PGS/OSD）场景实测反超（见 §3.2 V1.2 修订）。 |
| `dvmmrtable`（advancedsettings，预设代管下发） | MMR 色度查表 | **`true`** | **`true`** | **`true`** | N100 实测色度 pass 快 25.6%、整帧省 9.2%，输出逐位一致、无画质代价；全档开启。 |
| `videoscreen.hadesdvgamutfine` | 色域细分网格插值 | **`false`** | **`true`** | **`true`** | 高画质起启用约 3 倍精细度 3D LUT（约 201MB 显存、视频启动生成延迟数秒），误差缩至约 1/3；N100 标准档免此项开销。 |
| `videoscreen.hadesdvstepmode` | 掉帧安全防御步进 | **`2: LEVEL_1`**（V1.2） | **`0: AUTOMATIC`** | **`1: NEVER`** | 标准档锁 L1：字幕覆盖帧恒在预算内（实测 600/600 满帧），代价是干净帧也恒以 L1 渲染；高档位按需逐级降精度；独显锁定全精度。 |

### 3.2 composer 决策说明（高/极高 CCM；标准档 V1.2 改 libplacebo）

> **V1.2 修订（kodi-9999-g，2026-11-15）**：原决策"三档统一 CCM"仅基于**干净帧**实测。刷机后受控 A/B/C（双子 +10min PGS 字幕段）发现**覆盖帧**结论反转：CCM 覆盖帧 17.3–19.8ms（463–512/600，上游丢帧）vs libplacebo 17.0–17.8ms（547–568/600）vs **libplacebo+锁 L1 10.8–12.1ms（600/600 满帧、A/V 零漂移）**。标准档（弱卡定位）改 libplacebo+L1；高/极高档干净帧仍以 CCM 占优（13.7 vs 16.0ms），维持 CCM。

依据 `dvbridge_render.h`（`dvbridge_render_use_ccm_composer()` / `dvbridge_render_use_mmr_table()`）：

* 两条合成路径都基于 libplacebo 着色器基建：CCM = `pl_render_params.dovi_ccm`（libplacebo-9940），libplacebo reshaping 为对照实现（两者在 N100 上的实测对比见下）。
* 步进阶梯、路径选择（direct/composed）、ahead 模式的全部自适应机制及其跨会话持久化（`StepKept()`/`PathKept()`）**仅在 CCM 下工作**；libplacebo 期间测量一律不保留。
* 原稿"libplacebo 查表插值降 40%"系误记：真正的纹理查表优化是 CCM 自身的 `dovi_ccm_mmr_table`（advancedsettings `dvmmrtable`，逐位一致）。**N100 实测（2026-11-15，FEL MMR order-3 片源，工作区构建 A/B）**：表 ON 色度 pass **8.68ms** vs OFF **11.67ms**（**快 25.6%**），整帧 GPU 31.4 vs 34.6ms（**省 9.2%**）。注意：仅对 MMR 色度映射的片源生效（如 FEL；《双子杀手》为恒等多项式映射，开关无效果）；且每帧变更系数的流存在 CPU 重建表的反向风险（未见实例）。**标准档应下发 `dvmmrtable=true`**——当前源码默认为 false，与两个实验构建（均默认 true）的行为分歧需在实施时对齐。
* **N100 实测（2026-11-15，4K P7 FEL 测试 ISO，干净全屏帧，前瞻呈现）**：CCM 忠实 level 0 = **30.9–31.7ms/帧**，240/240 帧全速、零超期；libplacebo reshaping 忠实 level 0 = **45.7ms/帧**（超 35.5ms 预算，被迫降 level 1 后 33.4ms）。**libplacebo 比 CCM 慢约 46% 且需牺牲精度才能贴近**——"libplacebo 更省"假设在目标硬件上实测证伪，全档 CCM 的决策自此有数据支撑。
* 另一实测事实：**GUI 元素覆盖画面时 N100 GPU 成本翻倍**（63.8ms vs 干净帧 31.7ms，步进 level 1/2 均无增益）——前瞻呈现（83.4ms 预算）可吸收但呈现节奏拉伸（157/240 帧按时）。GUI 路径成本是比 FEL 更主要的过载源，属独立优化课题（tiles 机制 `dvdrawntiles` 已存在），不属本方案范围。
* CCM 覆盖不到的画面（luma MMR、异尺寸层等）无论设置如何都回退 libplacebo reshaping。
* libplacebo composer 保留为 expert 手选对照项，不进任何预设档位。

### 3.3 排除项：`videoscreen.hadesfloatoutput`

该设置**不纳入**画质档位矩阵。原因（依据 `kodi-9076` 与 `settings.md`）：
* 它是 **NVIDIA 专属**的显存缓冲格式开关（仅 nvidia-drm 显示，其余驱动上为空操作），无法作为跨厂商的画质档位杠杆；
* 其真实语义是 NVIDIA 无 10-bit 输出时"16-bit 浮点 vs 8-bit"的防断层选择，而非本方案初稿误述的"10-bit AR30 vs 16-bit RGBA16F"；
* 默认值为 On，与任何档位绑定都会翻转既有默认行为且对 Intel/AMD 无效。

该设置保持原样、原默认值，不随预设下发。

### 3.4 预设下发语义

* **写穿式（write-through）**：用户切换 `hadesqualitypreset` 时，一次性将矩阵中四个 GUI 底层值写入 `guisettings.xml`（沿用 `CDVEngineSettingsSync` 回调模式）。
* **`dvmmrtable` 的代管**：该项现仅存在于 advancedsettings.xml（无 GUI 设置 ID）。预设下发机制需扩展其一：实现为隐藏设置（推荐，纳入统一写穿），或由预设回调直接读写 advancedsettings 节点。实施时定夺，矩阵中已按全档 `true` 规划。
* 底层四项保留在设置树中（`level` 维持 expert/3），供进阶用户单独调整；手动改动后预设下拉框**不**回显"自定义"（Kodi spinner 无动态选项，接受此限制），但日志记录一行 `"quality preset: <n> overridden by manual change of <setting>"`。
* 预设值与手改值冲突时，**后写者胜**：预设切换会覆盖手改值，反之亦然。

---

## 四、 逐帧数据来源与全平台覆盖矩阵

"逐帧"的动态元数据有两条来源路径，覆盖度不同：

### 4.1 路径 1：元数据直读（与显卡无关，天然全覆盖）

| 片源类型 | 逐帧数据来源 | 实现位置 | 平台覆盖 |
|---|---|---|---|
| DV (P5/P7/P8) | RPU 中逐帧 L1（min/max/avg PQ） | `dvbridge_level1_effective()`（kodi-9999 引擎部分重落） | 全平台 ✓ |
| HDR10+ | ST 2094-40 逐帧转换 | `PlainHdr10Plus()` → `map_hdr10plus()` | 全平台 ✓ |

### 4.2 路径 2：GPU 测算（仅补无动态元数据的普通 HDR10/HLG）

双 Pass 降采样至 ~17KB PBO + 异步读回（`dvbridge_measure.c` / `dvbridge_measured_*`），seek/换片由 `m_dvMeasureEpoch` 重置。

| 平台 | 解码路径 | 现状 | 需要的工作 |
|---|---|---|---|
| Intel | VAAPI → `RendererVAAPIGLES`，`DVBRIDGE_P010` | ✓ 已覆盖（kodi-9999） | 引擎重落即可 |
| AMD | mesa VAAPI → 同上，P010 | 理论已覆盖 | 实测确认（RADV/RadeonSI + mesa VAAPI） |
| NVIDIA | NVDEC → `RendererDRMPRIMEGLES` | ✓ 代码已落地（kodi-9999-zzz3） | 真机实测确认（§7） |
| 软解 | `LinuxRendererGLES`，YUV420P10（R16 纹理） | ✓ 代码已落地（kodi-9999-zzz1/zzz2） | 实测确认（§7） |
| 测算不可用 | — | 回退现有静态 HDR10 元数据映射 | 不劣化现有行为 |

### 4.3 NVIDIA / 软解补齐方案

> **状态（2026-11-15）**：下列 1–3 已落地为 `kodi-9999-zzz1` / `kodi-9999-zzz2` / `kodi-9999-zzz3` 三份补丁（排序在 `kodi-9999-projector` 引擎补丁之后，沿用 `kodi-9995-zzz-` 的 zzz 惯例；全序列 989 个补丁按 `scripts/unpack` 的真实顺序模拟应用零失败，7 个改动文件终态与撰写内容逐字节一致），四个改动文件以构建树原始编译命令 `-fsyntax-only` 通过；构建与真机实测待执行（§7）。

1. **管道补齐**（✅ kodi-9999-zzz3）：`RendererDRMPRIMEGLES` 补齐整条 plain-mapping 管线——`Configure()` 按 `CLinuxRendererGLES` 的决策链判定（映射到 SDR / HDR10 自适应 / 都不做，含 `PlainMappingFailed` 闩锁与输出信令 fail-closed），`Render()` 分派，`RenderPlainMapping()` 以 `CDRMPRIMETextureYUV` 逐平面导入（与 VAAPI 的 P010 同构），参数传递与 `RendererVAAPIGLES` 对齐（`pts` / `duration` / `video` / `doviMetadata` / `serial`）。
2. **测量布局扩展**（✅ kodi-9999-zzz1/zzz2）：`dvbridge_measure` 新增 `dvbridge_measure_submit_planar()`——三平面 YUV420P10（U/V 各自 R16 纹理、10-bit 低位对齐，`code_mul`/`planar`/`chroma_v` uniform），原 `submit_ex` 变为共享内核的薄包装；窗口侧 `DVMeasurePicture()` / `RenderPlainMapping()` 解除 `layer.layout == DVBRIDGE_P010` 单一门控。DRM PRIME 的 P010 双平面复用现有导入路径，无需新增 EGL 导入。
3. **回退保证**（✅ kodi-9999-zzz3）：单张图映射失败即回退 Kodi 自绘；连续 48 张失败闩锁 `PlainMappingFailed` 并记日志，不中断播放。
4. 测算 Pass 在独显上开销可忽略；N100 上沿用现有"测算仅在有映射需求时运行"的门控（`dtmNeedsMeasure`）。

另：两渲染器的图片序列号已统一为 `DVBRIDGE::NextPictureSerial()`（进程级计数器，kodi-9999-zzz3），消除 LinuxRenderer 与 DRMPRIME 渲染器并存时的 serial 碰撞。

### 4.4 OSD 活跃降载

监听 `overlayFree`（`m_guiWillRender && GetGUIElementCount() == 0 && !m_dvOverlays`）：GUI 或字幕活跃时自动清零 `contrast_recovery`，保障低算力设备 OSD 场景零掉帧（kodi-9999 已实现，随引擎重落）。

---

## 五、 核心仲裁与执行层改造 (Arbitration & Pipeline Hooks)

### 5.1 压制 Native DV 抢占（`CWinSystemGbm::DVTurnedOff`）

若 `hadesdtmsdr` 或 `hadesdtmhdr` 为真，`DVTurnedOff()` 强制返回 `true`，切断私有 RGB 隧道信令，强行落入播放器 DTM 管线。

**调用点影响清单**（已核对 `WinSystemGbm.cpp`，共 3 处消费 + 定义）：

| 调用点 | 现行为 | DTM 开启后的预期行为 |
|---|---|---|
| `WinSystemGbm.cpp:1430` `SupportsNativeDVOutput()`（经 `NativeStateOf()`） | 返回 `SETTINGS` 状态：原生 DV 判为不可用 | 符合预期：低延迟 DV、HDMI 1.4b DV 信令、菜单 DV、DV 申报类型等全部下游随之关闭/摘除，统一走 DTM 输出 |
| `WinSystemGbm.cpp:1820` `NativeDVOutputReason()` | 返回 `"settings"` | **需修正**：DTM 激活时返回新理由串（如 `"dynamic tone mapping"`），避免播放器信息页误报"设置中关闭" |
| `WinSystemGbm.cpp:1939` `DVNewVideo()` 逐视频闩锁 + 日志 | 日志输出 "turned off in the settings" | 同上，日志措辞区分 DTM 接管与用户手关 |

### 5.2 输出信令与色彩空间锁相（`CWinSystemGbmGLESContext::ConfigChanged`）

* 若 `hadesdtmsdr` 开启：强制 `m_dvConvertDisplay = false`，`m_dvConvertSdr = true`，`m_hdrAsSdr = ALL`，DRM 输出纯净 10-bit SDR 并剥离 HDR 元数据（`HDR_OUTPUT_METADATA` 卸载）。
* **WCG-SDR 信令（实测未生效，新增内核侧工作项）**：kodi-9999 引擎的 `ConversionOutputSdr()` 已按 gamut 设置 `AVCOL_PRI_BT2020`，但 **N100 实机验证（2026-11-15，i915）BT.2020 与 BT.709 两轮的 AVI InfoFrame 逐字节相同、Extended Colorimetry 位全零**——SDR 输出实际按 BT.709 广播，色域被压缩。断裂点待定位（Kodi GBM 层未对 SDR 设置 DRM `Colorspace` 属性，或 i915 Hades 补丁的 SDR 路径忽略广色域）。修复前，SDR 分支的 BT.2020/P3 目标色域实际以 BT.709 输出。
* **DV→SDR 为不可达路径**：现有 `hadeshdrassdr` 枚举按设计不含 DV（仅 HLG/HDR10/HDR10+），HDR 显示器上 DV 无法经现有设置映射到 SDR——`hadesdtmsdr` 的强制接管是**新行为**，无法用现行设置预验证，实施时需专门自测。
* 若 `hadesdtmhdr` 开启：强制 `m_dvConvertDisplay = true`，`m_dvConvertSdr = false`，DRM 以 HDR10 输出并携带目标峰值静态元数据；原片 MaxCLL 透传策略沿用现状，不强行篡改。

### 5.3 解除 OSD 色调映射拦截（`CLinuxRendererGLES::CheckVideoParameters`）——曲线双层映射

"映射曲线"设置横跨两层，注入策略如下：

| 用户曲线选择 | 注入的 `m_ToneMapMethod`（解锁层） | `dvbridge_hdr10_mapping.curve`（着色器层） |
|---|---|---|
| BT.2390 | `VS_TONEMAPMETHOD_BT2390` (=4) | `DVBRIDGE_HDR10_CURVE_BT2390` |
| BT.2390 libplacebo knee | `VS_TONEMAPMETHOD_BT2390_LIBPLACEBO` (=5) | `DVBRIDGE_HDR10_CURVE_BT2390_LIBPLACEBO` |
| Spline | `VS_TONEMAPMETHOD_BT2390` (=4，仅作解锁) | spline 曲线 |

* 解锁层的目的是通过 `IsReferenceToneMapMethod()` 的拦截检查（kodi-9918 后含 4 与 5 两个合法值）；实际色调曲线由 dvbridge 着色器层决定。
* **注入为读取时覆盖**，不写入每视频持久化设置（`m_ToneMapMethod` 属 videodb 逐视频存储）；DTM 关闭后用户的逐视频选择（含 Off）恢复权威。

### 5.4 画质预设自动下发（`CWinSystemGbmGLESContext::TakeDVConversionMapping` & `DVEngineSettings`）

系统按 3.4 的写穿语义读取 `videoscreen.hadesqualitypreset`，向着色器下发对应的 `composer`、`gamutfine` 和 `stepmode` 策略；DTM 域参数（`dynamic_target = true`、`contrast_recovery`、目标白点/峰值/色域/曲线）在 `TakeDVConversionMapping()` 组装 `dvbridge_hdr10_mapping` 时注入。

---

## 六、 旧设置处置与 kodi-9999 拆分回退

### 6.1 kodi-9999 内容清单（13 个 diff 段，11 个文件）

**引擎部分（V1.1 依赖的核心，必须重落）**：

| 文件 | 内容 |
|---|---|
| `tools/dvbridge/dvbridge_placebo.h/.c` | `dynamic_target` + `contrast_recovery` 字段与校验、SDR 广色域（P3/BT.2020）合法性、black level 传入目标色空间、SDR 白点上限 1500 |
| `tools/dvbridge/dvbridge_render.h/.c` | `measured_l1` 逐帧 L1 贯穿 `render_hdr10()` / `dvbridge_render_plain()` / `dvbridge_render_hdr10()`；SDR 目标原色按 gamut 选择 |
| `xbmc/.../DVBridgeGLES.h/.cpp` | L1 参数、`ConversionOutputSdr()` 按 gamut 输出 WCG-SDR（BT.2020/P3/709） |
| `xbmc/.../LinuxRendererGLES.cpp` | `RenderPlainMapping` 元数据参数、pts/duration/video 传递 |
| `xbmc/.../RendererVAAPIGLES.cpp` | 同上（VAAPI 路径） |
| `xbmc/windowing/gbm/WinSystemGbmGLESContext.h/.cpp` | P010 异步测算接入 plain mapping、epoch/seek 重置、OSD 活跃清零 contrast_recovery、`DVMeasurePicture` 门控放宽 |

**设置部分（由 V1.1 新设置族替代）**：

| 文件 | 内容 |
|---|---|
| `system/settings/settings.xml`、`strings.po` | `hadesdvsdrgamut` / `hadesdvsdrcurve` / `hadesdtmrecovery` 三设置项及字符串 |
| `xbmc/settings/Settings.h` | 对应 SETTING 常量（重落时换成 V1.1 新 ID） |
| `WinSystemGbmGLESContext.cpp`（设置读取段） | 从旧三设置读值改为从 `hadesdtmsdr`/`hadesdtmhdr` 分支参数读值 |

### 6.2 处置方案

> **执行状态（2026-11-15）**：`kodi-9999-projector-dynamic-tone-mapping.patch` 已从序列移除（原件存档于工作区）；引擎部分已按 1–3 段原样重落为 `kodi-9999-a`（dvbridge 字段：dynamic_target / contrast_recovery / WCG-SDR 合法性 / 白点上限 1500）、`kodi-9999-b`（渲染器管道：measured_l1 贯穿、ConversionOutputSdr 按 gamut 输出）、`kodi-9999-c`（窗口测算接入：P010 异步测算、epoch/seek 重置、OSD 清零、门控放宽）；设置部分（settings.xml / strings.po / Settings.h 与两处旧设置读取）按计划不重落，由 V1.1 新设置族替代——`kodi-9999-d` 已定义两组新设置（分支 10/11，字符串 41854–41882）。**后续补丁均已落地**：`kodi-9999-e`（§5.1–5.4 仲裁层注入：`DtmToSdr/DtmToHdr/DtmTakesOutput/ToneMapMethodOf` 四助手、`DVTurnedOff()` 强制 true 与理由串/日志措辞、`DVConversionNewVideo()` 输出锁相、§5.4 三处 mapping 组装按新 ID 覆写并注入 dynamic_target/contrast_recovery、§2.1 双开 LOGWARNING + SDR 优先）、`kodi-9999-zzz4`（§7 曲线注入点清单的最后一项：两渲染器 `LibplaceboKneeWanted()` 的 knee 判定改由 DTM 曲线决定，排序在 zzz3 之后）、`kodi-9999-f`（§3.4 预设写穿 `CQualityPresetSync` 回调 + 手改日志、§6.3 一次性迁移——含部署版专有三 ID 的原始 XML 读取与采纳后 target 归零防再触发、§6.4 六设置隐藏、dvmmrtable 源码默认 true 及 DVBridgeGLES 注释/日志同步）。全序列 **995 补丁**模拟应用零失败，11 个改动文件终态与撰写稿逐字节一致，6 个触及 TU 以构建树原始编译命令 `-fsyntax-only` 全过。构建与真机实测待执行。

1. 从补丁序列移除 `kodi-9999-projector-dynamic-tone-mapping.patch`。
2. 新补丁序列按功能分段重落引擎部分（建议顺序：dvbridge 引擎字段 → 渲染器管道 → 测算接入 → 新设置族与 UI → 仲裁层注入）。
3. 引擎重落时把 6.1 表中的旧设置读取全部改指向 V1.1 新设置 ID。

### 6.3 旧值迁移（`guisettings.xml`，一次性行为）

| 旧设置 | 迁移动作 |
|---|---|
| `hadesdvsdrtarget` = 2 (Projector) / 3 (Custom) | 置 `hadesdtmsdr = true`，白点/Gamma 沿用 `hadesdvsdrwhite`/`hadesdvsdrgamma` 原值（白点上限已放宽至 1500，原值天然合法） |
| `hadesdvsdrgamut` / `hadesdvsdrcurve` | 携带至 SDR 分支的色域/曲线子项 |
| `hadesdtmrecovery` | 携带至对比度恢复子项 |
| `hadesdvsdrtarget` = 0/1 | 不迁移（维持关闭态） |

旧设置 ID 从 `settings.xml` 移除，不保留隐藏项（与 `hadesdvstepmode` 吸收旧布尔值的先例不同：本族旧值已完整迁移，无需兼容读取）。

### 6.4 映射类既有设置全面收编（kodi-9999 之外）

与 DTM 分支功能重叠的入口不止 kodi-9999 一族，以下设置若不收编，重构后 UI 仍呈"双头蛇"。处置原则：**UI 隐藏、ID 保留供迁移读取、引擎管线保留**。

| 既有设置 | 来源补丁 | 与新族的重叠 | 处置 |
|---|---|---|---|
| `hadesdvsdrtarget` / `hadesdvsdrwhite` / `hadesdvsdrgamma` | kodi-9698 / kodi-9850 | 与"映射到 SDR"的亮度/Gamma 子项同功能 | UI 隐藏，值迁移（见 6.3）；SDR target 解析与白点上限的引擎部分保留 |
| `hadeshdr10adapt` | kodi-9534 | 与"映射到 HDR"分支同功能（HDR10→显示自适应） | UI 隐藏；`hadesdtmhdr` 开启即强制 adapt 语义 |
| `hadesdvhdr10curve` | （HDR10→显示的曲线设置） | 与"映射曲线"子项同功能 | UI 隐藏，值迁移至曲线子项 |
| `hadeshdrassdr` | kodi-9877 | 与"映射到 SDR"主开关同功能 | UI 隐藏；`hadesdtmsdr` 开启即强制 `m_hdrAsSdr = ALL` |

各来源补丁（9698/9850/9534/9877）不整体回退——它们同时携带 DTM 引擎依赖的管线代码；只摘除/隐藏其设置 UI 并把读值改挂新族 ID。

---

## 七、 实施与验收

1. **补丁结构**：全部改动落于 `projects/Generic/patches/kodi/x86/`，编号顺延；每补丁单一主题，遵循仓库 STANDARDS.md。
2. **验证命令**（按 AGENTS.md，不自动执行全量构建）：
   ```bash
   PROJECT=Generic ARCH=x86_64 ./scripts/clean kodi && PROJECT=Generic ARCH=x86_64 ./scripts/build_mt kodi:target
   ./tools/pkgcheck kodi
   ```
3. **实测清单**：
   - [x] N100 composer 对比（2026-11-15，FEL RPU_EL 测试 ISO）：CCM 忠实级 30.9–31.7ms/帧（240/240 全速）vs libplacebo 忠实级 45.7ms/帧（降 level 1 后 33.4ms）。libplacebo 慢约 46%，全档 CCM 定稿。`dvmmrtable` 在部署构建上恒开且显式 false 无效，on/off 差异未能分离（见下条）。
   - [x] N100 复测（《双子杀手》4K P7 MEL @ 59.940fps，2026-11-15）：CCM 忠实级 13.6ms/帧（600/600 满帧，低于 14.2ms 前瞻平均预算）vs libplacebo 16.0ms/帧（超预算线，靠"无错过刷新"双证据规则才未降级）。libplacebo 慢约 18%；两种内容、两种帧率下结论一致：CCM 全面占优。
   - [x] MMR table A/B（2026-11-15，FEL ISO，工作区构建显式开关）：ON 8.68ms/31.4ms vs OFF 11.67ms/34.6ms——ON 色度 pass 快 25.6%、整帧省 9.2%，输出逐位一致。双子为多项式映射不适用此开关（实测确认）。另发现：两个实验构建默认 ON，当前源码默认 OFF。
   - [x] aheadmode 对照（双子 59.94Hz）：默认 "when needed" 即刻收敛为前瞻呈现，与 "always" 稳态等价（13.8 vs 13.7ms）——非默认值无收益，维持默认。
   - [x] N100 步进兜底（同日）：AUTOMATIC 正确探索 level 1（57.7ms）/level 2（58.7ms）后判定无增益回归忠实 level 0；干净帧 31.7ms 无掉帧；GUI 覆盖帧 63.8ms 由前瞻呈现吸收。FEL 全档不降级 + AUTOMATIC 兜底成立。
   - [x] DTM 映射路径 N100 行为学验证（2026-11-15，合成 4K PQ/BT.2020 HDR10 片 + `hadeshdrassdr=ALL` + Projector 目标 + 恢复 20%）：speed=1、0 underflow、0 丢帧——**行为学 PASS**。但该路径**无 10s 摘要与 pass 遥测**（DVBridge 前缀日志为零，`dvpasstimes` 不覆盖 plain mapping）→ 实施需补映射路径的耗时遥测，GPU 每帧成本至今未量化。
   - [x] WCG-SDR 信令验证（同日）：**未生效**——BT.2020 与 BT.709 目标下 AVI InfoFrame 逐字节相同（`12 28 04 00`，Extended Colorimetry 全零），SDR 实际按 BT.709 输出。
   - [x] 工作区构建已部署重跑（MMR A/B 即在其上完成；CCM 基线 31.4ms 与部署构建 31.3ms 一致，两构建性能基线吻合）。测毕已还原原生二进制。
   - [x] PGS 覆盖帧 composer A/B/C（2026-11-15，双子 +10min 字幕段，Hades-F1.0 刷机后受控复测）：**覆盖帧**成本 CCM 17.3–19.8ms（463–512/600 帧，上游丢 90–140 帧/10s）vs libplacebo 17.0–17.8ms（547–568/600）vs **libplacebo+锁 L1 10.8–12.1ms（600/600 满帧，A/V 零漂移）**；干净帧结论不变（CCM 13.7 vs libplacebo 16.0）。前两条 [x] 的"CCM 全面占优"仅对干净帧成立，PGS/OSD 覆盖密集场景 libplacebo+降档反超。
   - [ ] **V1.2 候选——预设矩阵 composer 处置**（2026-11-15 用户定夺：暂不动代码）：写穿对全档强制 CCM（`WriteThrough` 无条件 `SetInt(COMPOSER, 0)`，ultra 锁步进也只锁 level 0），无任何一档可达 libplacebo+锁档；而该组合是 PGS 字幕段唯一满帧配置。备选：high/ultra 改用 libplacebo / 写穿不再代管 composer / 预设日志行补列 composer（现状只报 FEL/gamut/步进，用户无从知晓 composer 被改）。刷机后"特效字幕变卡"即源于此：用户旧组合（libplacebo+锁档，guisettings 跨刷机存活，19:42:00.715 双 override 行为证）被预设循环写穿覆盖为 CCM+automatic。**已实施（kodi-9999-g/h/i，2026-11-15 晚）**：g=标准档改 libplacebo+锁 L1（矩阵见 §3.1 修订）+ 预设日志行补列合成器 + 隐藏四个预设代管项（fel/stepmode/composer/gamutfine，`visible=false`，GUI 不可改、RPC 仍可写）+ **源码默认值对齐标准矩阵（composer 默认 0→1、stepmode 0→2）**——写穿只在预设值变化时触发，若默认值不随矩阵改，"不动设置"的开箱状态就仍是旧矩阵、与帮助文案"标准=不动此项设置的播放方式"矛盾；h=设置页排序调整为 常规→画质→动态映射→HDR→Dolby Vision→…（组序 `1 11 10 2 7 8 9 6 3 4 5`；用户拍板"画质与 DTM 相邻、在 HDR 上方"）。**已三刷实测通过（2026-11-15 晚）**：中文界面确认 画质/动态映射 两组位于"HDR"上方、紧邻"常规"。**排序锚点复盘（2026-11-15 二刷实测）**：首版 h 把两个组挪到了组8（msgid 41106 "HDR on displays without Dolby Vision…"）之前——中文界面上用户读到的"HDR"却是**组2**（msgid 39191，zh 语言包译作"HDR"），画质仍在它下方，用户以"位置没在 HDR 上方"报障。Kodi 显示组序=文档顺序（`addISetting` 仅认 before/after 属性否则按文档序追加，解析/渲染全链路无排序；已核设备文件无这些属性），故修正=把插入锚点从组8改为组2（`<group id="2" label="39191">`），两个组落在"常规"之后、"HDR"之前；i=固件自带翻译机制（`LocalizeStrings::Load` 合并 `system/language-overrides/<语言插件id>.po`，`LoadPO` 翻译分支守卫放宽为"不在内存、或既有条目为英文占位（`strOriginal` 为空——en 回退分支只写 `strTranslated` 不写 `strOriginal`）、或原文一致时可覆盖"）+ `resource.language.zh_cn.po` 29 条（画质模式/DTM 两分支全部 label+help，皮肤语言包无法覆盖核心串的缺口由此补上）。**首轮刷机实测复盘（21:26 调试启动）**：覆盖文件被找到且解析，但 `loaded 0 strings`——首版守卫只比"msgid==strOriginal"，而 en 占位条目 `strOriginal` 为空串 → 29 条全被拒；补上 `strOriginal.empty()` 分支后修复。**既有盒子注意**：guisettings 里存的旧值（0/0）跨刷机存活且变为非默认值，刷机后需把画质模式切到 高 再切回 标准 一次（或经 RPC 触发写穿）方能落到新矩阵。**全新刷机验证（2026-11-15 实测）**：备份并删除 guisettings.xml 后重启 Kodi 模拟出厂首启——再生文件为 preset=0 / composer=1 / stepmode=2 全部 `default="true"`，且迁移钩子无操作被实证（再生文件在迁移运行后保存，stepmode 仍为 2 而非被改写为 NEVER(1)，stepdown/ahead 保持 true，sdrtarget=0 使 DTM 迁移不触发）；即全新刷机开箱即标准矩阵（libplacebo+锁L1），无需任何手动步骤。另注意：上游 Kodi 全新状态下 webserver 默认关闭（本机 RPC 探针不可达属预期），与矩阵无关。验证：998 补丁全序列模拟零失败、5 终态文件逐字节一致、XML 良构（display 分类组序 1 2 7 11 10 8 9 6 3 4 5）、两 TU `-fsyntax-only` 通过。
   - [ ] **内核侧工作项**：i915/DRM 对 SDR 广色域的 AVI Extended Colorimetry 信令（定位 Kodi GBM `Colorspace` 属性 vs i915 Hades 补丁 SDR 路径的断裂点并修复）——阻塞"模式 A"物理前提
   - [ ] 映射路径 pass 级遥测补齐后，量化 N100 上 HDR10→SDR 的每帧 GPU 成本
   - [x] **DTM 两分支真机生效验证（2026-11-15 晚，`le`/F1.0，双子 P7 MEL 三相对比）**：`hadesdtmhdr=true` → 仲裁触发（`native DV output unavailable: turned off in the settings`，随后 `taken by frame-by-frame dynamic tone mapping`）+ 输出切 HDR10（`HDR10 goes out as YCbCr 4:2:0 at 10 bits`，dmesg 出现 DRM HDR static metadata InfoFrame、DV vendor InfoFrame 消失）；`hadesdtmsdr=true` → `Dolby Vision rebuilt and mapped to an output that takes no HDR10: to its SDR signal (BT.709, a pure 1.8 power as its EOTF, its white at 500 cd/m2…)`（**目标白点/Gamma 设置值被引擎逐字回显=参数真实喂入映射**）+ dmesg DRM InfoFrame off（SDR 输出）。两相位播放无 error/丢帧。原"现有设置不可达，无法预验证"结论推翻：设置 GUI 一级可见、RPC 可写、生效。**未闭环**：画面内容随目标值变化的视觉确认（需人眼/亮度计）；映射路径无 10s 摘要遥测（见上条）。
   - [ ] AMD mesa VAAPI 路径测算确认
   - [ ] NVIDIA DRM PRIME 测算补齐后的正确性与回退行为（代码已落地：kodi-9999-zzz1/zzz2/zzz3，2026-11-15；全序列 989 补丁模拟应用零失败 + `-fsyntax-only` 通过；待 `./scripts/clean kodi && ./scripts/build_mt kodi:target` 构建与真机实测）
- [ ] 软解 YUV420P10 三平面路径的实测确认（同上，代码已落地）
   - [ ] SDR/HDR 两分支默认值（白点/Gamma/恢复量）在电视与投影仪上的校准
   - [ ] `DVTurnedOff()` 强制 true 后播放器信息页理由串与日志措辞
4. **实施注意事项**：
   * **曲线注入点清单**（§5.3 的"读取时覆盖"必须覆盖全部消费点）：`CLinuxRendererGLES::CheckVideoParameters`、`DVBRIDGE::WantsPlainMapping`/`WantsConversion`、`ConversionTargetOf`/`ConversionEligible`（demuxer hint 路径）、`RenderPlainMapping` 调用链。漏一处即静默回退。**已全部落地**：前三组在 `kodi-9999-e`（`ConversionEligible` 委托 `ConversionTargetOf`，随其头注入传递覆盖），最后一组（两渲染器 `LibplaceboKneeWanted()` 的 knee 判定与 ConfigChanged 触发器）在 `kodi-9999-zzz4`。
   * **HLG 内容**：无动态元数据，逐帧数据仅能走 GPU 测算（现受 P010 门控）；与 libplacebo-9981 的 HLG 名义峰值调优（`hadeslimit` 一族）的取值关系需在实施时定义。
   * **`dvmmrtable` 源码默认值与实验构建分歧**：当前源码默认 false，两个实验构建默认 true——实施时统一（按实测 ON 更优，倾向改源码默认或按 §3.4 预设代管下发）。**已定夺（kodi-9999-f）**：源码默认改为 true（实测 ON 快且逐位一致、全档位矩阵均为 true，无预设代管必要），`AdvancedSettings` 注释与 `DVBridgeGLES` 日志文案已同步。
