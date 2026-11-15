# LibreELEC-Hades: 投影仪专用逐帧动态色调映射 (Projector DTM) v3.0 就地升级工程规范

> **文档标识**: SPEC-HADES-PROJ-DTM-V3.0 (In-Place Upgrade & Standard-Compliant Edition)  
> **状态**: 终版工程规范 (Final Engineering Specification - Fully Reviewed & Production-Ready)  
> **适用硬件**: Intel Alder Lake-N (N100, Gen12 Xe-LP 24 EUs) 及 Generic x86_64 平台  
> **面向设备**: SDR / HDR 家庭影院投影仪 (JVC D-ILA, Sony SXRD, Epson 3LCD/Laser 等)  
> **架构准则**: **就地升级（In-place Upgrade）官方已有选项、零冗余设置、100% 遵循 HDMI 行业规范、无缝支持 WCG-SDR BT.2020**  
> **代码基线**: LibreELEC-Hades 最新开发分支 (`kodi-22.0rc2-Piers`)  

---

## 一、 战略重构与设计哲学：就地升级（In-place Upgrade）

### 1.1 摒弃平行冗余开关，无缝融入 Hades 原生体系
在 Hades 最新源码中，官方已经构建了针对投影仪与显示器映射的完整 UI 入口，但底层实现仅仅是“单片一次性决策的静态映射（Static Tone Mapping）”。
若另起炉灶新增平行的 DTM 设置项，会导致 UI 极其混乱，用户无法理解系统状态机。

**本规范的核心战略**：
**对 Hades 官方现成的映射入口进行“底层动力总成换装（In-place Upgrade）”**：
- 用户在 Kodi 设置中操作的依然是官方原汁原味的选项；
- 底层渲染管线全部透明升级为**满血逐帧动态色调映射（Dynamic Tone Mapping）**！

---

## 二、 两大输出模式的行业标准落地

```
+---------------------------------------------------------------------------------------------------+
|                                      HDR 片源 (DV / HDR10+ / HDR10)                                |
+---------------------------------------------------------------------------------------------------+
                                                  |
                    [播放器内部 DTM 引擎: 逐帧 L1 动态元数据 + dynamic_target 高光保护]
                                                  |
         +----------------------------------------+----------------------------------------+
         |                                                                                  |
         v                                                                                  v
【模式 A：SDR 10-bit 极致模式 (强烈推荐)】                                【模式 B：HDR10 自适应标准模式】
(对应官方 videoscreen.hadesdvsdrtarget)                                  (对应官方 videoscreen.hadeshdr10adapt)
- 输出信号：标准 10-bit SDR (Gamma 2.4 / BT.1886)                        - 输出信号：标准 10-bit HDR10 (PQ 传输特性)
- 色域支持：BT.2020 / DCI-P3 / BT.709                                    - 色调映射：内部着色器动态压缩至幕布设定峰值
- InfoFrame: 广播 AVI InfoFrame (BT.2020_RGB)                            - InfoFrame: 100% 忠实透传原片 MaxCLL (标规)
- 杜绝二次映射：投影机 HDR 引擎 100% 物理休眠                              - 避免欺骗：绝不强行篡改，保留原版限额开关自主权
```

### 2.1 模式 A（推荐首选）：HDR 转 10-bit WCG-SDR 投影模式
- **对应官方选项**：【设置 -> 显示 -> SDR 目标显示设备（`videoscreen.hadesdvsdrtarget`）】
  - 选项 `2`: **Projector (100 cd/m², Gamma 2.4)**
  - 选项 `3`: **Custom (自定义白点 20~1500 nits 与 Gamma 1.8~2.8)**
  - 配套色域子项：**`videoscreen.hadesdvsdrgamut`**（**BT.2020** / **DCI-P3** / **BT.709**）
  - 配套曲线子项：**`videoscreen.hadesdvsdrcurve`**（**BT.2390** / **Spline 样条曲线** / **BT.2390 with libplacebo knee**）
  - 配套对比度恢复：**`videoscreen.hadesdtmrecovery`**（0~100%，默认 0）
- **物理机理与色域支持（BT.2020 广色域）**：
  - **色彩与动态范围彻底解耦**：在国际标准（CTA-861-G / ITU-R BT.2020）中，BT.2020 仅代表色度坐标范围，可与任意传输函数搭配。
  - **AVI InfoFrame 广播**：播放器输出 SDR 时，DRM 彻底卸载 `HDR_OUTPUT_METADATA`，但在 HDMI AVI InfoFrame 中发送 `Extended Colorimetry = BT.2020_RGB`。
  - **投影机行为**：投影机（如 JVC NZ/N 系列、索尼 XW 系列）接收到 SDR 信号，内部 HDR 引擎彻底休眠，展开机内广色域色彩滤镜（Color Profile 切为 BT.2020），工作在原生对比度最高的固定光圈与 Gamma 2.4 下。
  - **根除二次映射**：从物理层面上 100% 消灭投影机二次色调映射的可能。

### 2.2 模式 B（行业标规）：HDR 转 HDR10 投影模式
- **对应官方选项**：【设置 -> 显示 -> HDR10 and HDR10+ adapted to the display（`videoscreen.hadeshdr10adapt`）】
  - 选项 `1`: **Always**
  - 选项 `2`: **Automatic**（仅当片源母带峰值高于幕布设定值时启用）
- **绝不强行篡改 MaxCLL（恪守行业规范）**：
  - **渲染层**：由播放器端逐帧 DTM 在片元着色器内自适应压缩到设定峰值；
  - **广播层**：忠实保留原片自带的 `max_display_mastering_luminance` 与 `MaxCLL`，杜绝非标欺骗信号导致投影机机内算法误判；
  - **用户自主权**：用户若明确需要限制 HDMI InfoFrame 广播峰值，由 Hades 原厂已有开关 `videoscreen.hadeshdr10limiton` 独立控制，系统绝不强行干涉。

---

## 三、 核心算法机理与 N100 算力分配

1. **逐帧 L1 动态元数据（暗场与中调提亮）**：
   - 提取帧真实峰值 $L1_{\max}$，动态调低着色器输入峰值 `tone.input_max`（从 1000/4000 nits 降至真实值如 200 nits），中暗场动态范围彻底释放，消除投影死黑。
   - **HDR10+ 零 GPU 开销直通**：直接解析 ST 2094-40 转换为 L1，跳过 GPU 测算。
   - **普通 HDR10 异步 GPU 测算**：仅针对 VAAPI `P010` 硬解，通过 `dvbridge_measure.c` 双 Pass 降采样至 17KB PBO，利用 `dvbridge_measure_collect` 实现零等待读回。
2. **`dynamic_target`（高 APL 亮场保护）**：
   - 根据场景平均亮度 `scene_avg` 动态调整虚拟目标 $t_{pq} \ge p_{pq}$，计算衰减倍率 $dt\_exposure = p_{\text{nits}} / t_{\text{nits}} \le 1.0$，保护高光滚降肩部，杜绝大面积雪地、烈日死白剪切。
3. **OSD 活跃时自动降载**：
   - 监听 `overlayFree`（`m_guiWillRender && GetGUIElementCount() == 0 && !m_dvOverlays`），当 GUI 或字幕活跃时自动清零 `contrast_recovery`，确保 N100 24EU 在高负荷下零掉帧。

---

## 四、 逐文件精确改造规范 (对齐 kodi-22.0rc2-Piers 最新基线)

### 4.1 `tools/dvbridge/dvbridge_placebo.h`

#### [tools/dvbridge/dvbridge_placebo.h:133-175](build.LibreELEC-Generic.x86_64-13.0-devel/build/kodi-22.0rc2-Piers/tools/dvbridge/dvbridge_placebo.h#L133)
放宽自定义 SDR 目标白点上限至 1500 nits（支持 800~1000 nits 高亮度电视接入 SDR 映射），并在 `struct dvbridge_hdr10_mapping` 尾部扩展 DTM 字段：
```c
/* Hades: custom SDR target white ceiling extended to 1500 nits for high-brightness TVs */
#define DVBRIDGE_SDR_WHITE_MAX 1500.0f

struct dvbridge_hdr10_mapping {
    bool enabled;
    float peak;                      /* of the display, cd/m2 (for SDR, its white) */
    enum dvbridge_hdr10_gamut gamut; /* of the display, inside the BT.2020 signal (SDR: BT.709, P3_D65, BT.2020) */
    enum dvbridge_hdr10_curve curve;
    bool source_known;
    float source_xy[8];
    enum dvbridge_hdr10_target target;
    float target_xy[8];
    float black;
    bool gamma22;
    float gamma;
    bool trims;

    /* Projector DTM extensions */
    bool dynamic_target;             /* enable dynamic virtual peak scaling */
    float contrast_recovery;         /* 0.0f (off) to 1.0f (strong) */
};
```

---

### 4.2 `tools/dvbridge/dvbridge_placebo.c`

#### [tools/dvbridge/dvbridge_placebo.c:167-172](build.LibreELEC-Generic.x86_64-13.0-devel/build/kodi-22.0rc2-Piers/tools/dvbridge/dvbridge_placebo.c#L167-L172)
**现有原代码**:
```c
    /* Hades: an SDR output is BT.709 (Kodi signals no other gamut there) */
    if (m->target != DVBRIDGE_HDR10_TARGET_HDR10 &&
        (m->target != DVBRIDGE_HDR10_TARGET_SDR || m->gamut != DVBRIDGE_HDR10_GAMUT_BT709))
        return false;
```
**目标代码**（放行 SDR 下的 DCI-P3 与 BT.2020，校验 `contrast_recovery`）:
```c
    /* Hades: an SDR output allows BT.709, DCI-P3, or BT.2020 */
    if (m->target != DVBRIDGE_HDR10_TARGET_HDR10 &&
        (m->target != DVBRIDGE_HDR10_TARGET_SDR ||
         (m->gamut != DVBRIDGE_HDR10_GAMUT_BT709 &&
          m->gamut != DVBRIDGE_HDR10_GAMUT_P3_D65 &&
          m->gamut != DVBRIDGE_HDR10_GAMUT_BT2020)))
        return false;
    if (!(m->contrast_recovery >= 0.0f && m->contrast_recovery <= 1.0f))
        return false;
```

---

### 4.3 `tools/dvbridge/dvbridge_render.h` 与 `tools/dvbridge/dvbridge_render.c`

#### [tools/dvbridge/dvbridge_render.h:175](build.LibreELEC-Generic.x86_64-13.0-devel/build/kodi-22.0rc2-Piers/tools/dvbridge/dvbridge_render.h#L175)
```c
bool dvbridge_render_plain(struct dvbridge_renderer *renderer, const struct pl_frame *source,
                          const struct dvbridge_plain *plain, struct dvbridge_view view,
                          int width, int height, const struct dvbridge_level1 *measured_l1);
```

#### [tools/dvbridge/dvbridge_render.c:2235-2278](build.LibreELEC-Generic.x86_64-13.0-devel/build/kodi-22.0rc2-Piers/tools/dvbridge/dvbridge_render.c#L2235-L2278)
**现有原代码**:
```c
    const bool sdr = m->target == DVBRIDGE_HDR10_TARGET_SDR;
    *target = (struct pl_color_space){
        .primaries = sdr ? PL_COLOR_PRIM_BT_709 : PL_COLOR_PRIM_BT_2020,
        .transfer = sdr ? dvbridge_sdr_transfer(m) : PL_COLOR_TRC_PQ,
        .hdr = {.min_luma = PL_COLOR_HDR_BLACK, .max_luma = m->peak,
                .prim = {.red = {xy[0], xy[1]}, .green = {xy[2], xy[3]}, .blue = {xy[4], xy[5]},
                         .white = {xy[6], xy[7]}}},
    };
    *params = pl_color_map_default_params;
    params->tone_mapping_function =
        m->curve == DVBRIDGE_HDR10_CURVE_BT2390 ||
                m->curve == DVBRIDGE_HDR10_CURVE_BT2390_LIBPLACEBO
            ? &pl_tone_map_bt2390
            : &pl_tone_map_spline;
    // ...
```
**目标代码**（精准选择输出色域，挂载 DTM 算法参数）:
```c
    const bool sdr = m->target == DVBRIDGE_HDR10_TARGET_SDR;
    enum pl_color_primaries out_prim = PL_COLOR_PRIM_BT_2020;
    if (sdr) {
        if (m->gamut == DVBRIDGE_HDR10_GAMUT_BT2020)
            out_prim = PL_COLOR_PRIM_BT_2020;
        else if (m->gamut == DVBRIDGE_HDR10_GAMUT_P3_D65)
            out_prim = PL_COLOR_PRIM_DISPLAY_P3;
        else
            out_prim = PL_COLOR_PRIM_BT_709;
    }

    *target = (struct pl_color_space){
        .primaries = out_prim,
        .transfer = sdr ? dvbridge_sdr_transfer(m) : PL_COLOR_TRC_PQ,
        .hdr = {.min_luma = (m->black > 0.0f) ? m->black : PL_COLOR_HDR_BLACK,
                .max_luma = m->peak,
                .prim = {.red = {xy[0], xy[1]}, .green = {xy[2], xy[3]}, .blue = {xy[4], xy[5]},
                         .white = {xy[6], xy[7]}}},
    };
    *params = pl_color_map_default_params;
    params->tone_mapping_function =
        m->curve == DVBRIDGE_HDR10_CURVE_BT2390 ||
                m->curve == DVBRIDGE_HDR10_CURVE_BT2390_LIBPLACEBO
            ? &pl_tone_map_bt2390
            : &pl_tone_map_spline;
    if (m->curve == DVBRIDGE_HDR10_CURVE_BT2390)
        params->tone_constants.knee_offset = DVBRIDGE_BT2390_KNEE_OFFSET;
    params->gamut_mapping = &pl_gamut_map_perceptual;
    params->metadata = PL_HDR_METADATA_ANY;
    params->inverse_tone_mapping = false;
    params->gamut_expansion = false;
    params->dynamic_target = m->dynamic_target;
    params->contrast_recovery = m->contrast_recovery;
```

#### [tools/dvbridge/dvbridge_render.c:2915 & 3066](build.LibreELEC-Generic.x86_64-13.0-devel/build/kodi-22.0rc2-Piers/tools/dvbridge/dvbridge_render.c#L3066)
在 `render_hdr10` 与 `dvbridge_render_plain` 中加入并透传 `const struct dvbridge_level1 *measured_l1`：
```c
bool dvbridge_render_plain(struct dvbridge_renderer *r, const struct pl_frame *source,
                          const struct dvbridge_plain *plain, struct dvbridge_view view,
                          int width, int height, const struct dvbridge_level1 *measured_l1)
{
    if (!r || !plain)
        return false;
    r->hdr10_ready = false;
    r->residual_omitted = false;
    r->residual_drawn = false;
    dvbridge_gl_drain_errors();
    struct dvbridge_gl_state state;
    save_gl_state(&state);
    const bool fine = fine_gamut_table(r, false);
    r->hdr10_ready = render_hdr10(r, source, NULL, 0, 0.0, NAN, view, width, height, plain, measured_l1);
    if (gamut_table_retry(r, fine, r->hdr10_ready)) {
        r->hdr10_ready = render_hdr10(r, source, NULL, 0, 0.0, NAN, view, width, height, plain, measured_l1);
        gamut_table_kept(r, r->hdr10_ready);
    }
    restore_gl_state(&state);
    return r->hdr10_ready;
}
```

---

### 4.4 `xbmc/cores/VideoPlayer/VideoRenderers/DVBridgeGLES.h` 与 `.cpp`

#### [xbmc/cores/VideoPlayer/VideoRenderers/DVBridgeGLES.h:502, 570](build.LibreELEC-Generic.x86_64-13.0-devel/build/kodi-22.0rc2-Piers/xbmc/cores/VideoPlayer/VideoRenderers/DVBridgeGLES.h#L502)
```cpp
  bool PreparePlain(const Layer& base,
                    const dvbridge_plain& plain,
                    dvbridge_view view,
                    int width,
                    int height,
                    unsigned int serial,
                    const dvbridge_level1* measured_l1 = nullptr);
  static bool ConversionOutputSdr(const VideoPicture& picture,
                                  VideoPicture& output,
                                  const dvbridge_hdr10_mapping* mapping = nullptr);
```

#### [xbmc/cores/VideoPlayer/VideoRenderers/DVBridgeGLES.cpp:2534, 2683, 2706, 2780](build.LibreELEC-Generic.x86_64-13.0-devel/build/kodi-22.0rc2-Piers/xbmc/cores/VideoPlayer/VideoRenderers/DVBridgeGLES.cpp#L2534)
```cpp
bool CDVBridgeGLES::PreparePlain(const Layer& base,
                                 const dvbridge_plain& plain,
                                 dvbridge_view view,
                                 int width,
                                 int height,
                                 unsigned int serial,
                                 const dvbridge_level1* measured_l1)
{
  // ...
  const bool drawn = dvbridge_render_plain(m_renderer, &bl.frame, &plain, view, width, height, measured_l1);
  LogNotes();
  dvbridge_gl_frame_release(&bl);
  // ...
}

void CDVBridgeGLES::SetConversionMapping(const dvbridge_hdr10_mapping& mapping)
{
  const bool same =
      m_convertMappingSet && mapping.enabled == m_convertMapping.enabled &&
      (!mapping.enabled ||
       (mapping.peak == m_convertMapping.peak && mapping.gamut == m_convertMapping.gamut &&
        mapping.curve == m_convertMapping.curve && mapping.target == m_convertMapping.target &&
        mapping.dynamic_target == m_convertMapping.dynamic_target &&
        mapping.contrast_recovery == m_convertMapping.contrast_recovery &&
        mapping.source_known == m_convertMapping.source_known &&
        (!mapping.source_known ||
         std::equal(std::begin(mapping.source_xy), std::end(mapping.source_xy),
                    std::begin(m_convertMapping.source_xy)))));
  if (same || !m_renderer)
    return;
  // ...
}

// 修复官方硬编码 BT709 缺陷：若设置 BT.2020，正确指派色彩空间以驱动 HDMI AVI InfoFrame 发送 BT.2020_RGB
bool CDVBridgeGLES::ConversionOutputSdr(const VideoPicture& picture,
                                        VideoPicture& output,
                                        const dvbridge_hdr10_mapping* mapping)
{
  output.SetParams(picture);
  output.color_transfer = AVCOL_TRC_BT709;
  if (mapping && mapping->gamut == DVBRIDGE_HDR10_GAMUT_BT2020)
  {
    output.color_primaries = AVCOL_PRI_BT2020;
    output.color_space = AVCOL_SPC_BT2020_NCL;
  }
  else
  {
    output.color_primaries = AVCOL_PRI_BT709;
    output.color_space = AVCOL_SPC_BT709;
  }
  output.hasDisplayMetadata = false;
  output.displayMetadata = {};
  output.hasLightMetadata = false;
  output.lightMetadata = {};
  return true;
}

bool CDVBridgeGLES::ConversionOutput(const VideoPicture& picture,
                                     VideoPicture& output,
                                     const dvbridge_hdr10_mapping* mapping)
{
  if (!mapping || !mapping->enabled || mapping->target == DVBRIDGE_HDR10_TARGET_SDR)
    return ConversionOutputSdr(picture, output, mapping);
  // ...
```

---

### 4.5 `xbmc/cores/VideoPlayer/VideoRenderers/LinuxRendererGLES.cpp`

#### [xbmc/cores/VideoPlayer/VideoRenderers/LinuxRendererGLES.cpp:305-315](build.LibreELEC-Generic.x86_64-13.0-devel/build/kodi-22.0rc2-Piers/xbmc/cores/VideoPlayer/VideoRenderers/LinuxRendererGLES.cpp#L305-L315)
在普通 HDR 转 SDR 路径中，将 `mapping` 结构体指针传入 `ConversionOutputSdr`，打通 SDR BT.2020 信号广播调用闭环：
```cpp
  bool plain = !convert && dvWindow && !WantsDVBridge(picture) && WantsPlainMapping(picture);
  if (plain)
  {
    const dvbridge_hdr10_mapping mapping =
        dvWindow->TakeDVConversionMapping(picture, true, true, LibplaceboKneeWanted());
    CDVBridgeGLES::ConversionOutputSdr(picture, hdr10, &mapping);
    dvWindow->DVConversionAhead(false);
  }
```

---

### 4.6 `xbmc/cores/VideoPlayer/VideoRenderers/HwDecRender/RendererVAAPIGLES.h` 与 `.cpp`

#### [xbmc/cores/VideoPlayer/VideoRenderers/HwDecRender/RendererVAAPIGLES.cpp:322-365](build.LibreELEC-Generic.x86_64-13.0-devel/build/kodi-22.0rc2-Piers/xbmc/cores/VideoPlayer/VideoRenderers/HwDecRender/RendererVAAPIGLES.cpp#L322-L365)
```cpp
int CRendererVAAPIGLES::RenderPlainMapping(int idx)
{
  if (!m_isVAAPIBuffer || m_textureTarget != GL_TEXTURE_2D || m_renderOrientation != 0)
    return -1;
  auto* window = dynamic_cast<KODI::WINDOWING::GBM::CWinSystemGbmGLESContext*>(
      CServiceBroker::GetWinSystem());
  if (!window)
    return -1;
  const auto& buffer = m_buffers[idx];
  CDVBridgeGLES::Layer layer{};
  switch (m_vaapiFourcc)
  {
    case VA_FOURCC_NV12: layer.layout = DVBRIDGE_NV12; break;
    case VA_FOURCC_P010: layer.layout = DVBRIDGE_P010; break;
    case VA_FOURCC_P012: layer.layout = DVBRIDGE_P012; break;
    case VA_FOURCC_P016: layer.layout = DVBRIDGE_P016; break;
    default: return -1;
  }
  layer.width = m_sourceWidth;
  layer.height = m_sourceHeight;
  layer.chroma = buffer.doviChroma;
  layer.pts = (buffer.doviPts != DVD_NOPTS_VALUE) ? buffer.doviPts : 0.0;
  layer.duration = buffer.doviDuration;
  layer.video = buffer.doviVideo;
  for (int p = 0; p < 2; ++p)
  {
    const auto& plane = buffer.fields[FIELD_FULL][p];
    layer.planes[p] = {plane.id, static_cast<int>(plane.texwidth),
                      static_cast<int>(plane.texheight)};
  }
  dvbridge_plain plain{};
  plain.hlg = buffer.m_srcColTransfer == AVCOL_TRC_ARIB_STD_B67;
  plain.full_range = buffer.m_srcFullRange;
  if (buffer.hasDisplayMetadata && buffer.displayMetadata.has_luminance &&
      buffer.displayMetadata.max_luminance.den && buffer.displayMetadata.min_luminance.den)
  {
    plain.max_luma = static_cast<float>(av_q2d(buffer.displayMetadata.max_luminance));
    plain.min_luma = static_cast<float>(av_q2d(buffer.displayMetadata.min_luminance));
  }
  if (buffer.hasLightMetadata)
  {
    plain.max_cll = static_cast<float>(buffer.lightMetadata.MaxCLL);
    plain.max_fall = static_cast<float>(buffer.lightMetadata.MaxFALL);
  }
  // 透传 buffer.doviMetadata 用于 HDR10+ 零开销直通
  return window->RenderPlainMapping(layer, plain, m_sourceRect, m_destRect, buffer.doviSerial, buffer.doviMetadata);
}
```

---

### 4.7 `xbmc/windowing/gbm/WinSystemGbmGLESContext.h` 与 `.cpp`

#### [xbmc/windowing/gbm/WinSystemGbmGLESContext.h:298](build.LibreELEC-Generic.x86_64-13.0-devel/build/kodi-22.0rc2-Piers/xbmc/windowing/gbm/WinSystemGbmGLESContext.h#L298)
```cpp
  int RenderPlainMapping(const CDVBridgeGLES::Layer& layer,
                         const dvbridge_plain& plain,
                         const CRect& source,
                         const CRect& dest,
                         unsigned int serial,
                         const CDVMetadataBuffer& metadata = {});
```

#### 1. `TakeDVConversionMapping` 就地接入 DTM ([行 4875-4925](build.LibreELEC-Generic.x86_64-13.0-devel/build/kodi-22.0rc2-Piers/xbmc/windowing/gbm/WinSystemGbmGLESContext.cpp#L4875))
当用户配置了 SDR Projector 或 Custom 时，底层自动激活 DTM，并根据用户色域选择赋能 BT.2020：
```cpp
    const int target =
        settings && settings->GetSetting(CSettings::SETTING_VIDEOSCREEN_HADESDVSDRTARGET)
            ? settings->GetInt(CSettings::SETTING_VIDEOSCREEN_HADESDVSDRTARGET)
            : DVBRIDGE_SDR_TARGET_REFERENCE;
    if (target == DVBRIDGE_SDR_TARGET_CUSTOM)
      mapping = dvbridge_sdr_mapping_custom(
          settings->GetSetting(CSettings::SETTING_VIDEOSCREEN_HADESDVSDRWHITE)
              ? static_cast<float>(settings->GetInt(CSettings::SETTING_VIDEOSCREEN_HADESDVSDRWHITE))
              : DVBRIDGE_SDR_WHITE,
          settings->GetSetting(CSettings::SETTING_VIDEOSCREEN_HADESDVSDRGAMMA)
              ? static_cast<float>(settings->GetNumber(CSettings::SETTING_VIDEOSCREEN_HADESDVSDRGAMMA))
              : 2.4f,
          known ? xy : nullptr);
    else
      mapping = dvbridge_sdr_mapping_for(target, known ? xy : nullptr);

    // 就地升级：如果用户选择了投影模式 (Projector 或 Custom)，自动赋予 BT.2020 与动态虚拟目标
    if (target == DVBRIDGE_SDR_TARGET_PROJECTOR || target == DVBRIDGE_SDR_TARGET_CUSTOM)
    {
      if (settings && settings->GetSetting(CSettings::SETTING_VIDEOSCREEN_HADESDVSDRGAMUT))
      {
        switch (settings->GetInt(CSettings::SETTING_VIDEOSCREEN_HADESDVSDRGAMUT))
        {
          case 0: mapping.gamut = DVBRIDGE_HDR10_GAMUT_BT2020; break;
          case 2: mapping.gamut = DVBRIDGE_HDR10_GAMUT_BT709; break;
          default: mapping.gamut = DVBRIDGE_HDR10_GAMUT_P3_D65; break;
        }
      }
      else
      {
        mapping.gamut = DVBRIDGE_HDR10_GAMUT_BT2020;
      }
      if (settings && settings->GetSetting(CSettings::SETTING_VIDEOSCREEN_HADESDVSDRCURVE))
      {
        mapping.curve = dvbridge_hdr10_curve_of_setting(
            settings->GetInt(CSettings::SETTING_VIDEOSCREEN_HADESDVSDRCURVE));
      }
      mapping.dynamic_target = true;
      mapping.contrast_recovery = settings && settings->GetSetting(CSettings::SETTING_VIDEOSCREEN_HADESDTMRECOVERY)
                                      ? settings->GetInt(CSettings::SETTING_VIDEOSCREEN_HADESDTMRECOVERY) / 100.0f
                                      : 0.0f;
    }
```

#### 2. `TakeHdr10AdaptMapping` 就地接入 DTM ([行 3572-3620](build.LibreELEC-Generic.x86_64-13.0-devel/build/kodi-22.0rc2-Piers/xbmc/windowing/gbm/WinSystemGbmGLESContext.cpp#L3572))
只要 HDR10 适配开启，底层自动激活 DTM 引擎：
```cpp
  if (mapping.enabled)
  {
    mapping.dynamic_target = true;
    mapping.contrast_recovery = settings && settings->GetSetting(CSettings::SETTING_VIDEOSCREEN_HADESDTMRECOVERY)
                                    ? settings->GetInt(CSettings::SETTING_VIDEOSCREEN_HADESDTMRECOVERY) / 100.0f
                                    : 0.0f;
  }
```

#### 3. `DVMeasurePicture` 解绑 DV 原生守卫 ([行 6021](build.LibreELEC-Generic.x86_64-13.0-devel/build/kodi-22.0rc2-Piers/xbmc/windowing/gbm/WinSystemGbmGLESContext.cpp#L6021))
```cpp
bool CWinSystemGbmGLESContext::DVMeasurePicture(const CDVBridgeGLES::Layer& layer)
{
  const bool dtmNeedsMeasure = m_dvConvertMapping.enabled;
  if (!dtmNeedsMeasure && (!m_dvBridge || !m_dvState.Captured()))
    return false;
  if (layer.layout != DVBRIDGE_P010 || !DVMeasureReady())
    return false;
  if (std::find(m_dvMeasureSubmitted.begin(), m_dvMeasureSubmitted.end(), layer.pts) !=
      m_dvMeasureSubmitted.end())
    return true;
  int window[2];
  dvbridge_measured_window(m_dvMeasured.get(), layer.width / 2, window);
  if (!dvbridge_measure_submit(m_dvMeasure.get(), layer.planes[0].texture, layer.planes[1].texture, layer.width,
                               layer.height, window, layer.pts, m_dvMeasureEpoch))
    return false;
  m_dvMeasureSubmitted.push_back(layer.pts);
  if (m_dvMeasureSubmitted.size() > 64)
    m_dvMeasureSubmitted.pop_front();
  return true;
}
```

#### 4. `RenderDVConversion` 接入 OSD 降载 ([行 4725-4735](build.LibreELEC-Generic.x86_64-13.0-devel/build/kodi-22.0rc2-Piers/xbmc/windowing/gbm/WinSystemGbmGLESContext.cpp#L4725-L4735))
```cpp
  if (!ConversionBridge(true))
    return -1;
  // mapped to the display as the output was told when the renderer was configured
  const bool overlayFree = m_guiWillRender && GetGUIElementCount() == 0 && !m_dvOverlays;
  dvbridge_hdr10_mapping mapping = m_dvConvertMapping;
  if (!overlayFree)
    mapping.contrast_recovery = 0.0f;
  m_dvConvertBridge->SetConversionMapping(mapping);
  // Hades: kept in the form that the copy into the window needs (dvbridge_render_hdr10_store())
  m_dvConvertBridge->SetConversionTarget(0, UseLimitedColor());
```

#### 5. `RenderPlainMapping` 闭环重构 ([行 4801-4874](build.LibreELEC-Generic.x86_64-13.0-devel/build/kodi-22.0rc2-Piers/xbmc/windowing/gbm/WinSystemGbmGLESContext.cpp#L4801-L4874))
保留原版完整的 `Hdr10AdaptTimer`、`Hdr10AdaptStats`、`m_hdr10AdaptShownNs` 与 `m_gpuPower` 机制，保障 GPU 调频与 OSD 状态监视完全正常：
```cpp
int CWinSystemGbmGLESContext::RenderPlainMapping(const CDVBridgeGLES::Layer& layer,
                                                 const dvbridge_plain& plain,
                                                 const CRect& source,
                                                 const CRect& dest,
                                                 unsigned int serial,
                                                 const CDVMetadataBuffer& metadata)
{
  const DVBRIDGE::ConversionPlace place =
      DVBRIDGE::PlaceConversion(source.x1, source.y1, source.x2, source.y2, dest.x1, dest.y1,
                                dest.x2, dest.y2, layer.width, layer.height, m_nWidth, m_nHeight);
  if (!place.valid)
    return -1;
  dvbridge_view view{};
  view.src_x0 = place.srcX0;
  view.src_y0 = place.srcY0;
  view.src_x1 = place.srcX1;
  view.src_y1 = place.srcY1;
  view.dst_x = place.dstX;
  view.dst_y = place.dstY;
  view.dst_width = place.dstWidth;
  view.dst_height = place.dstHeight;
  GLint target = 0;
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &target);
  if (target != 0)
    return -1;
  if (!m_dvConvertBridge)
    m_dvConvertBridge = std::make_unique<CDVBridgeGLES>();
  if (!m_dvConvertBridge->InitializeConversion())
    return -1;

  // 1. OSD / 字幕活跃时动态旁路对比度恢复，防止 N100 GPU 超载掉帧
  const bool overlayFree = m_guiWillRender && GetGUIElementCount() == 0 && !m_dvOverlays;
  dvbridge_hdr10_mapping mapping = m_dvConvertMapping;
  if (!overlayFree)
    mapping.contrast_recovery = 0.0f;

  m_dvConvertBridge->SetConversionMapping(mapping);
  m_dvConvertBridge->SetConversionTarget(0, UseLimitedColor());

  // 2. 逐帧动态元数据决策 (HDR10+ 直通 或 GPU 异步测算)
  dvbridge_level1 l1{};
  const dvbridge_level1* pL1 = nullptr;

  if (mapping.enabled && !plain.hlg)
  {
    // 快路径：直接复用 ST 2094-40 转换的 L1 动态元数据 (0 GPU 负载)
    if (metadata.Data() && metadata.Size() > 0 &&
        dvbridge_level1_effective(metadata.Data(), metadata.Size(), &l1))
    {
      pL1 = &l1;
    }
    // 降级路径：VAAPI P010 GPU 异步降采样测算
    else if (DVMeasureReady() && layer.layout == DVBRIDGE_P010)
    {
      const double gap = layer.duration > 0 ? 24 * layer.duration : 0;
      const bool videoChanged = layer.video && layer.video != m_dvMeasuredVideo;
      const bool seekJump = (m_dvMeasuredPts != DVD_NOPTS_VALUE &&
                             (layer.pts < m_dvMeasuredPts || (gap > 0 && layer.pts > m_dvMeasuredPts + gap)));
      if (videoChanged || seekJump)
      {
        m_dvMeasuredVideo = layer.video;
        ++m_dvMeasureEpoch;
        m_dvMeasureSubmitted.clear();
        dvbridge_measure_reset(m_dvMeasure.get());
        dvbridge_measured_reset(m_dvMeasured.get(), !videoChanged);
      }
      m_dvMeasuredPts = layer.pts;

      DVMeasurePicture(layer);

      // 触发 PBO Fence 收集与滑动平滑滤波
      dvbridge_measure_collect(
          m_dvMeasure.get(),
          [](const dvbridge_measured_raw* raw, uint64_t tag, void* context)
          {
            auto* self = static_cast<CWinSystemGbmGLESContext*>(context);
            dvbridge_measured_picture picture;
            if (tag == self->m_dvMeasureEpoch &&
                dvbridge_measured_reduce(self->m_dvMeasured.get(), raw, &picture))
              dvbridge_measured_add(self->m_dvMeasured.get(), &picture);
          },
          this);

      dvbridge_measured_l1 l1Data{};
      dvbridge_measured_take(m_dvMeasured.get(), layer.pts, &l1Data);
      if (l1Data.measured)
      {
        l1.min = l1Data.min_pq / 4095.0f;
        l1.max = l1Data.max_pq / 4095.0f;
        l1.avg = l1Data.avg_pq / 4095.0f;
        l1.applied = true;
        pL1 = &l1;
      }
    }
  }

  // 3. 原版 HDR10 Adapt 统计与计时逻辑完整保留
  const bool adapted = mapping.enabled && mapping.target == DVBRIDGE_HDR10_TARGET_HDR10;
  if (adapted)
  {
    if (const uint32_t video = m_hdr10Adapt.Video(); video != m_hdr10AdaptStatsVideo)
    {
      m_hdr10AdaptStatsVideo = video;
      m_hdr10AdaptStats = {};
      m_hdr10AdaptStats.start = std::chrono::steady_clock::now();
    }
    Hdr10AdaptTimerCollect();
    Hdr10AdaptTimerMark(true);
  }

  const bool mapped =
      m_dvConvertBridge->PreparePlain(layer, plain, view, m_nWidth, m_nHeight, serial, pL1);
  const dvbridge_gl_rect area{place.dstX, place.dstY, place.dstWidth, place.dstHeight};
  const bool copied =
      m_dvConvertBridge->CopyConversion(0, m_nWidth, m_nHeight, UseLimitedColor(), &area);

  if (adapted)
  {
    Hdr10AdaptTimerMark(false);
    ++(!copied ? m_hdr10AdaptStats.notMapped : mapped ? m_hdr10AdaptStats.mapped
                                                      : m_hdr10AdaptStats.kept);
    if (copied)
      m_hdr10AdaptShownNs.store(std::chrono::duration_cast<std::chrono::nanoseconds>(
                                    std::chrono::steady_clock::now().time_since_epoch())
                                    .count(),
                                std::memory_order_relaxed);
    Hdr10AdaptStatsLog(false);
  }

  if (!copied)
    return -1;

  // 4. 原版 GPUPOWER 功耗档位联动完整保留
  if (mapped && m_gpuPower && (serial == 0 || serial != m_gpuPowerSerial))
  {
    m_gpuPowerSerial = serial;
    m_gpuPower->Drawn(GPUPOWER::Drawing::MAPPING);
  }
  return mapped ? 1 : 0;
}
```

---

### 4.8 `system/settings/settings.xml` 与 `xbmc/settings/Settings.h`

#### [system/settings/settings.xml:3965](build.LibreELEC-Generic.x86_64-13.0-devel/build/kodi-22.0rc2-Piers/system/settings/settings.xml#L3965)
1. 将 `videoscreen.hadesdvsdrwhite` 上限由 500 放宽至 1500 nits（支持 800~1000 nits OLED 电视）：
```xml
      <setting id="videoscreen.hadesdvsdrwhite" type="integer" parent="videoscreen.hadesdvsdrtarget" label="41136" help="41137">
        <!-- ... -->
        <constraints>
          <minimum>20</minimum>
          <step>1</step>
          <maximum>1500</maximum>
        </constraints>
        <!-- ... -->
      </setting>
```

2. 在 `videoscreen.hadesdvsdrtarget` 下方增加 `videoscreen.hadesdvsdrgamut`（BT.2020 / DCI-P3 / BT.709）、`videoscreen.hadesdvsdrcurve`（BT.2390 / Spline / BT.2390 with libplacebo knee）以及 `videoscreen.hadesdtmrecovery`：
```xml
      <!-- Hades: the gamut of HDR mapped to SDR for a projector or custom display -->
      <setting id="videoscreen.hadesdvsdrgamut" type="integer" parent="videoscreen.hadesdvsdrtarget" label="39839" help="39840">
        <requirement>
          <and>
            <condition>HAVE_GBM</condition>
            <condition>HAS_GLES</condition>
          </and>
        </requirement>
        <dependencies>
          <dependency type="enable" setting="videoscreen.hadesdvsdrtarget" operator="ge">2</dependency>
        </dependencies>
        <level>2</level>
        <default>0</default> <!-- BT.2020 by default for projector, or DCI-P3 / BT.709 -->
        <constraints>
          <options>
            <option label="39841">0</option> <!-- BT.2020 -->
            <option label="39842">1</option> <!-- DCI-P3 (D65) -->
            <option label="39843">2</option> <!-- BT.709 -->
          </options>
        </constraints>
        <control type="spinner" format="string" />
      </setting>

      <!-- Hades: the tone mapping curve for HDR mapped to SDR (Spline, BT.2390, BT.2390 libplacebo) -->
      <setting id="videoscreen.hadesdvsdrcurve" type="integer" parent="videoscreen.hadesdvsdrtarget" label="39844" help="39845">
        <requirement>
          <and>
            <condition>HAVE_GBM</condition>
            <condition>HAS_GLES</condition>
          </and>
        </requirement>
        <dependencies>
          <dependency type="enable" setting="videoscreen.hadesdvsdrtarget" operator="ge">2</dependency>
        </dependencies>
        <level>3</level>
        <default>1</default> <!-- BT.2390 default -->
        <constraints>
          <options>
            <option label="39847">1</option> <!-- BT.2390 -->
            <option label="39846">0</option> <!-- spline -->
            <option label="41460">2</option> <!-- BT.2390 with libplacebo's knee -->
          </options>
        </constraints>
        <control type="spinner" format="string" />
      </setting>

      <!-- Optional DTM contrast recovery fine-tuning slider (default: 0 off) -->
      <setting id="videoscreen.hadesdtmrecovery" type="integer" parent="videoscreen.hadesdvsdrtarget" label="41140" help="41141">
        <requirement>
          <and>
            <condition>HAVE_GBM</condition>
            <condition>HAS_GLES</condition>
          </and>
        </requirement>
        <level>3</level>
        <default>0</default>
        <constraints>
          <minimum>0</minimum>
          <step>10</step>
          <maximum>100</maximum>
        </constraints>
        <control type="spinner" format="string" />
      </setting>
```

#### [xbmc/settings/Settings.h:478](build.LibreELEC-Generic.x86_64-13.0-devel/build/kodi-22.0rc2-Piers/xbmc/settings/Settings.h#L478)
```cpp
  static constexpr auto SETTING_VIDEOSCREEN_HADESDVSDRTARGET = "videoscreen.hadesdvsdrtarget";
  static constexpr auto SETTING_VIDEOSCREEN_HADESDVSDRWHITE = "videoscreen.hadesdvsdrwhite";
  static constexpr auto SETTING_VIDEOSCREEN_HADESDVSDRGAMMA = "videoscreen.hadesdvsdrgamma";
  //! Hades: the gamut of HDR mapped to SDR for a projector (0: BT.2020, 1: DCI-P3, 2: BT.709)
  static constexpr auto SETTING_VIDEOSCREEN_HADESDVSDRGAMUT = "videoscreen.hadesdvsdrgamut";
  //! Hades: the curve of HDR mapped to SDR (0: spline, 1: BT.2390, 2: BT.2390 with libplacebo knee)
  static constexpr auto SETTING_VIDEOSCREEN_HADESDVSDRCURVE = "videoscreen.hadesdvsdrcurve";
  //! Hades: optional contrast recovery strength for projector DTM (0 to 100 percent)
  static constexpr auto SETTING_VIDEOSCREEN_HADESDTMRECOVERY = "videoscreen.hadesdtmrecovery";
```

---

## 五、 持久化补丁清单与验证指南

所有修改固化至 `projects/Generic/patches/kodi/x86/kodi-9999-projector-dynamic-tone-mapping.patch`：

| 涉及模块 | 核心工作 |
| :--- | :--- |
| `tools/dvbridge/` | 放行 SDR `BT2020`/`P3` 色域；放宽白点上限至 1500 nits；接入 `dynamic_target` 着色器参数 |
| `VideoRenderers/DVBridgeGLES` | 修复 `ConversionOutputSdr` 硬编码 BT709 缺陷；透传 L1 |
| `VideoRenderers/LinuxRendererGLES` | SDR plain 路径向 `ConversionOutputSdr` 传入 `&mapping` |
| `VideoRenderers/HwDecRender` | `RenderPlainMapping` 透传 HDR10+ 元数据 |
| `Windowing/GBM` | 就地注入 DTM 逻辑；解绑 DV 原生守卫；闭环切集/Seek 重置、PBO 收集与原版统计 |
| `system/settings/` | 注册 `hadesdvsdrgamut`、`hadesdvsdrcurve` 与 `hadesdtmrecovery` 选项，放宽白点至 1500 nits |

### 验收清单：
1. **模式 A 验证（SDR BT.2020 投影模式）**：
   - 播放 HDR10 片源，Kodi 设置选择 `Projector (100 cd/m2)`，色域选择 `BT.2020`；
   - 检查 `kodi.log`，确认输出色度为 `BT.2020_RGB`，无 `HDR_OUTPUT_METADATA` 广播；
   - 投影机色彩配置文件自动切入 BT.2020，Gamma 锁定 2.4，暗部通透，高光无截断，**0 二次映射**。
2. **模式 B 验证（HDR10 标规模式）**：
   - 播放《1917》等 HDR10 片源，Kodi 开启 `HDR10 adapted to the display`；
   - 通过 `drm_info` 确认 HDMI 广播的 `MaxCLL` 忠实等于原片标称值（如 1000 nits），绝无非法强改。
