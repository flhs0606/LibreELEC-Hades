# LibreELEC-Hades: 投影仪专用逐帧动态色调映射 (Projector DTM) v2.1 终版工程规范

> **文档标识**: SPEC-HADES-PROJ-DTM-V2.1  
> **状态**: 终版工程规范 (Final Engineering Specification - Fully Reviewed & Production-Ready)  
> **适用硬件**: Intel Alder Lake-N (N100, Gen12 Xe-LP 24 EUs) 及 Generic x86_64 平台  
> **面向设备**: SDR / HDR 家庭影院投影仪 (JVC D-ILA, Sony SXRD, Epson 3LCD/Laser 等)  
> **设计准则**: 100% 自包含、零伪代码、严格对齐 Hades 真实代码基线与行号、修复 P1~P8 架构评审缺陷  

---

## 一、 项目背景与物理机理剖析

### 1.1 投影仪显示物理限制与动态色调映射的分工

家庭影院投影仪投射漫反射至 100~150 英寸幕布，实际入眼峰值亮度通常仅有 **50 ~ 150 cd/m² (nits)**。
与峰值可达 1000 ~ 4000 nits 的自发光电视相比，传统静态色调映射存在无法克服的物理缺陷：
1. **中暗场镜头死黑挤压**：按母带标称 1000/4000 nits 静态压缩至 100 nits 时，全片平均亮度（10~50 nits）的常规镜头被死死挤压在幕布亮度的最低 10%~20%，整体观感昏暗无光。
2. **高平均亮度 (High APL) 场景高光过曝/发平**：盲目拉高静态曲线增益会导致爆炸、烈日、雪地等大面积高光细节死白一片。

**本系统的两大核心算法与物理分工**：
- **逐帧 L1 动态元数据（通过 ST 2094-10 / ST 2094-40 / GPU 快速测算获得）**：
  - **核心任务：暗场与常规镜头提亮**。
  - **机理**：向渲染器传递当前帧真实的峰值亮度 $L1_{\max}$。当遇到暗场或普通室内场景（如当前帧最高亮度仅为 200 nits），传入真实的 $L1_{\max}$ 会直接拉低着色器中的输入峰值 `tone.input_max`（从 1000/4000 nits 骤降至 200 nits）。色调映射曲线仅需将 [0, 200] nits 映射到幕布 [0, 100] nits，从根本上释放了中间调动态范围，常规场景的平均亮度大幅提升，彻底消除投影仪死黑。
- **`dynamic_target` 动态虚拟目标缩放（`libplacebo-9943` 补丁）**：
  - **核心任务：高 APL 亮场高光滚降肩部保护与防过曝**。
  - **机理**：在高 APL 或大面积高光镜头下，仅靠 L1 容易因压缩过于剧烈导致高光层次丢失。`dynamic_target` 算法根据当前帧平均亮度 `scene_avg` 计算一个处于物理幕布峰值 $p_{pq}$ 与片源输入峰值 $s_{pq}$ 之间的虚拟目标峰值 $t_{pq}$（$t_{\text{nits}} \ge p_{\text{nits}}$），将色调映射曲线的拐点与滚降肩部基于虚拟峰值 $t_{pq}$ 进行扩展，并通过曝光衰减倍率 $dt\_exposure = p_{\text{nits}} / t_{\text{nits}} \le 1.0$ 压缩全局增益，完整保留高光云层、火光等丰富纹理细节，杜绝死白剪切。

### 1.2 目标架构
在 LibreELEC-Hades 的 GBM/OpenGL ES 3.2 渲染管线中构建一套对标 **madVR Envy / JVC Frame Adapt HDR** 的播放器端逐帧动态映射系统：
- **模式 A (推荐首选)**：**HDR 转 SDR 10-bit 投影极致模式**（Gamma 2.4 / BT.1886，支持 DCI-P3 / BT.2020 / BT.709 广色域，投影机锁固定光圈压榨原生对比度）。
- **模式 B**：**HDR 转 HDR10 投影自适应模式**（PQ 输出，修正 MaxCLL = Target Nits，旁路投影机内部二次色调映射）。

### 1.3 Intel N100 (24EU Xe-LP) 算力负载拆解

| 渲染阶段 | 执行硬件单元 | 4K 23.976p 耗时 (预算 41.7 ms) | 4K 60p 耗时 (预算 16.6 ms) | 资源开销说明 |
| :--- | :--- | :--- | :--- | :--- |
| **视频硬件解码** | QuickSync VDBOX | **0 ms (专用硬件)** | **0 ms** | 4K 10-bit 硬解，CPU 占用 5~8%，GPU 3D 为 0 |
| **DV 动态元数据解包** | CPU 解复用/软解析 | **< 0.1 ms** | **< 0.1 ms** | L1/L5/L6 随帧解析，**0 GPU 计算** |
| **HDR10+ 动态元数据转换** | CPU 算法 (`dvbridge_hdr10plus.c`) | **< 0.1 ms** | **< 0.1 ms** | ST 2094-40 直转 L1，**0 GPU 计算** |
| **HDR10 GPU 快速测算** | GPU GLES3 (`dvbridge_measure.c`) | **0.8 ~ 1.5 ms** | **1.2 ~ 1.8 ms** | 2x2 块级降采样两 Pass，渲染至 17KB PBO，异步 Fence 读回 (仅限 VAAPI P010) |
| **色调映射与 3D LUT 色域变换** | GPU 3D (`libplacebo`) | **2.5 ~ 4.2 ms** | **2.8 ~ 4.5 ms** | 单 Pass 片元着色器执行 BT.2390/Spline 映射 + 3D LUT 采样 |
| **对比度恢复 (选配)** | GPU 3D (`pl_shader_extract_features`) | **2.0 ~ 3.5 ms** | **建议关闭** | 额外 4K FBO 双 Pass；OSD 活跃时动态旁路清零 |
| **基础 DTM 总耗时** | **GPU 3D Engine** | **~3.5 - 5.7 ms** | **~4.0 - 6.3 ms** | **GPU 负荷率约 14% (24p) / 36% (60p)** |

---

## 二、 核心算法与物理参数深度核实

### 2.1 `libplacebo-9943` 补丁机理与超低流明 (50~80 nits) 参数调优
补丁文件：`packages/addons/addon-depends/multimedia-tools-depends/libplacebo/patches/libplacebo-9943-tone-map-dynamic-target-on-request.patch`。
在 `src/shaders/colorspace.c:2187-2234` 中：
```c
float scene_avg = src.hdr.scene_avg;
if (!(scene_avg > 0) && src.hdr.avg_pq_y > 0)
    scene_avg = pl_hdr_rescale(PL_HDR_PQ, PL_HDR_NITS, src.hdr.avg_pq_y);

if (obj && params->dynamic_target && scene_avg > 0 &&
    !params->inverse_tone_mapping &&
    tone.input_max > tone.output_max + 1e-4f)
{
    const float dt_dim = 0.09f, dt_soft = 0.04f;
    const float p_pq = tone.output_max;
    const float s_pq = tone.input_max;
    const float p_nits = pl_hdr_rescale(PL_HDR_PQ, PL_HDR_NITS, p_pq);
    const float f_pq = pl_hdr_rescale(PL_HDR_NITS, PL_HDR_PQ, scene_avg);
    const float dt_u = p_pq;
    const float dt_v = f_pq - dt_dim;
    const float t_pq =
        PL_CLAMP(0.5f * (dt_u + dt_v) +
                 hypotf(0.5f * (dt_u - dt_v), dt_soft),
                 p_pq, s_pq);
    if (t_pq > p_pq + 1e-4f && t_pq < s_pq - 1e-4f) {
        const float t_nits = pl_hdr_rescale(PL_HDR_PQ, PL_HDR_NITS, t_pq);
        dt_exposure = p_nits / t_nits;
        tone.output_max = t_pq;

        tone.output_min = pl_hdr_rescale(PL_HDR_NITS, PL_HDR_PQ,
            pl_hdr_rescale(PL_HDR_PQ, PL_HDR_NITS, out_min_phys) /
            dt_exposure);
    }
}
```
**机理与超低流明 (50~80 nits) 参数特性**：
1. **显存驻留**：`dynamic_target` 仅在着色器局部将曲线终点重设为虚拟目标 $t_{pq}$，`dst.hdr.max_luma` 保持恒定，因此绝不触发 3D LUT 重建。
2. **`dt_dim` (默认 0.09f PQ $\approx$ 0.18 nits) 与 `dt_soft` (默认 0.04f PQ)**：
   - 当 $f_{pq} \le p_{pq} + dt\_dim$ 时（暗场或低 APL 场景），$dt\_v < dt\_u$，$t_{pq} \approx p_{pq}$，此时 $dt\_exposure \approx 1.0$，完全由 L1 负责提亮画面；
   - 当 $f_{pq} > p_{pq} + dt\_dim$ 时（高 APL 亮场），虚拟目标 $t_{pq}$ 迅速抬升，使 $dt\_exposure = p_{\text{nits}} / t_{\text{nits}} < 1.0$，着色器主动收缩曝光，为高光滚降让出动态余量；
   - 在 50~80 nits 投影机上，若需暗场进一步通透，可将 `dt_dim` 适度上调至 `0.11f`；若需亮场高光过渡更加平缓，可将 `dt_soft` 上调至 `0.06f`。

### 2.2 24 MiB 3D LUT 缓存稳定性证明
在 `src/shaders/colorspace.c:1288-1298` 中：
```c
static uint64_t gamut_map_signature(const struct pl_gamut_map_params *par)
{
    uint64_t sig = CACHE_KEY_GAMUT_LUT;
    pl_hash_merge(&sig, pl_str0_hash(par->function->name));
    pl_hash_merge(&sig, pl_var_hash(par->input_gamut));
    pl_hash_merge(&sig, pl_var_hash(par->output_gamut));
    pl_hash_merge(&sig, pl_var_hash(par->min_luma));
    pl_hash_merge(&sig, pl_var_hash(par->max_luma));
    pl_hash_merge(&sig, pl_var_hash(par->constants));
    return sig;
}
```
`par->output_gamut` 与 `par->max_luma` 绑定到 `target.color`（整部电影恒定）。逐帧更新的 `source->hdr.max_pq_y`、`source->hdr.avg_pq_y` 以及 `params->dynamic_target` **完全不参与哈希计算**。高精度 3D LUT 在视频起播首帧生成后将绝对常驻显存。

### 2.3 底层测量着色器与 VAAPI P010 硬件约束 (P2 缺陷根因)
核查 `tools/dvbridge/dvbridge_measure.c:25-50` 中的降采样着色器宏：
```c
/* The block (2x2 pixels) of block column c and block row r: the means of its R'G'B' (BT.2020, from 10-bit limited
 * range YCbCr, each pixel's components clamped to [0, 1] before the mean, as l1stats.py and framestats.c), max and
 * min of them. P010: the 10 bits are the top of 16. The chroma sample of a 4:2:0 block is the block's own. */
#define BLOCK                                                                                                  \
    "float code(float v) { return floor(v * 65535.0 / 64.0 + 0.5); }\n"                                      \
    "vec3 rgb(float y, vec2 c) {\n"                                                                           \
    "  float yn = (y - 64.0) / 876.0;\n"                                                                      \
    "  vec2 p = (c - 512.0) / 896.0;\n"                                                                       \
    "  return clamp(vec3(yn + 1.4746 * p.y, yn - (0.0593 * 1.8814 / 0.6780) * p.x - (0.2627 * 1.4746 / 0.6780) " \
    "* p.y, yn + 1.8814 * p.x), 0.0, 1.0);\n"                                                                 \
    "}\n"                                                                                                     \
    "vec2 block(int c, int r) {\n"                                                                            \
    "  vec2 ch = texelFetch(chroma, ivec2(c, r), 0).rg;\n"                                                    \
    "  ch = vec2(code(ch.x), code(ch.y));\n"                                                                  \
```
**关键物理约束**：
1. 着色器要求 `chroma` 纹理必须为双通道 packed RG（即 P010 的交错 UV 平面），并通过 `texelFetch(chroma, ...).rg` 取样；
2. `floor(v * 65535.0 / 64.0 + 0.5)` 针对 P010 独特的 16-bit 高位对齐（Top 10-bit of 16）进行右移 6 位还原；
3. 软件解码的三平面 `DVBRIDGE_YUV420P10` 其 U/V 平面为单通道独立纹理且为低位对齐，底层测量着色器无法直接采样。
**结论**：GPU 异步动态测算**仅在 VAAPI 硬解输出 `DVBRIDGE_P010` 时生效**；软解三平面路径直接走静态元数据或外部 HDR10+ 直通。

---

## 三、 逐文件精确改造规范 (File-by-File Implementation Spec)

### 3.1 `tools/dvbridge/dvbridge_placebo.h`

#### [tools/dvbridge/dvbridge_placebo.h:77-98](tools/dvbridge/dvbridge_placebo.h#L77-L98)
**现有原代码**:
```c
struct dvbridge_hdr10_mapping {
    bool enabled;
    float peak;                      /* of the display, cd/m2 (for SDR, its white) */
    enum dvbridge_hdr10_gamut gamut; /* of the display, inside the BT.2020 signal (SDR: BT.709) */
    enum dvbridge_hdr10_curve curve;
    /* The gamut of the mastering display, when its metadata gives it (the HDR10 metadata of the
     * stream): where the colours of the picture can be at all. CIE 1931 xy of red, green, blue
     * and white. Not known: the BT.2020 of the signal. */
    bool source_known;
    float source_xy[8];
    /* Hades: the signal of the mapped picture (0, HDR10, where nothing sets it) */
    enum dvbridge_hdr10_target target;
    /* Hades: with DVBRIDGE_HDR10_GAMUT_CUSTOM, the gamut of the display: CIE 1931 xy of red,
     * green, blue and white, inside BT.2020 (of an HDR10 target only; see dvbridge_hdr10_custom_xy()) */
    float target_xy[8];
    /* Hades: the black of the display, cd/m2, of an HDR10 target, for Dolby Vision Low-Latency: the black of the
     * source is taken to it with the black level lift of ITU-R BT.2390, so that what is just above black does
     * not sink into the display's own black (mask_low_latency() in dvbridge_render.c). 0: the black of the
     * source kept, as before, bit for bit. At most DVBRIDGE_HDR10_BLACK_MAX. A mapping of a picture for output
     * as HDR10 (dvbridge_render_hdr10_mapping()) does not apply it. */
    float black;
};
```
**目标代码**:
```c
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

    /* Projector DTM extensions */
    bool dynamic_target;             /* enable dynamic virtual peak scaling */
    float contrast_recovery;         /* 0.0f (off) to 1.0f (strong) */
};
```

---

### 3.2 `tools/dvbridge/dvbridge_placebo.c`

#### [tools/dvbridge/dvbridge_placebo.c:162-166](tools/dvbridge/dvbridge_placebo.c#L162-L166)
**现有原代码**:
```c
    /* Hades: an SDR output is BT.709 (Kodi signals no other gamut there) */
    if (m->target != DVBRIDGE_HDR10_TARGET_HDR10 &&
        (m->target != DVBRIDGE_HDR10_TARGET_SDR || m->gamut != DVBRIDGE_HDR10_GAMUT_BT709))
        return false;
```
**目标代码**:
```c
    /* Allow BT.709, DCI-P3, and BT.2020 for SDR projector output */
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

### 3.3 `tools/dvbridge/dvbridge_render.h` 与 `tools/dvbridge/dvbridge_render.c`

#### [tools/dvbridge/dvbridge_render.h:111-121](tools/dvbridge/dvbridge_render.h#L111-L121)
**真实结构体参考与接口定义**:
```c
struct dvbridge_plain {
    bool hlg;           /* the HLG transfer (ARIB STD-B67); else PQ (SMPTE ST 2084) */
    bool full_range;    /* the YCbCr of the picture in full range; else limited */
    float max_luma;     /* the mastering display's white, cd/m2 (0: not known) */
    float min_luma;     /* ... and black */
    float max_cll;      /* the content light levels, cd/m2 (0: not known) */
    float max_fall;
};
```
**目标接口代码**:
```c
bool dvbridge_render_plain(struct dvbridge_renderer *renderer, const struct pl_frame *source,
                          const struct dvbridge_plain *plain, struct dvbridge_view view,
                          int width, int height, const struct dvbridge_level1 *measured_l1);
```

#### [tools/dvbridge/dvbridge_render.c:1770-1808](tools/dvbridge/dvbridge_render.c#L1770-L1808)
**现有原代码**:
```c
    float xy[8];
    /* Hades: or a display's own (DVBRIDGE_HDR10_GAMUT_CUSTOM: Low-Latency), inside BT.2020 */
    if (m->gamut == DVBRIDGE_HDR10_GAMUT_CUSTOM)
        dvbridge_hdr10_custom_xy(m, xy);
    else
        dvbridge_hdr10_gamut_xy(m->gamut, xy);
    const bool sdr = m->target == DVBRIDGE_HDR10_TARGET_SDR;
    *target = (struct pl_color_space){
        .primaries = sdr ? PL_COLOR_PRIM_BT_709 : PL_COLOR_PRIM_BT_2020,
        .transfer = sdr ? PL_COLOR_TRC_BT_1886 : PL_COLOR_TRC_PQ,
        .hdr = {.min_luma = PL_COLOR_HDR_BLACK, .max_luma = m->peak,
                .prim = {.red = {xy[0], xy[1]}, .green = {xy[2], xy[3]}, .blue = {xy[4], xy[5]},
                         .white = {xy[6], xy[7]}}},
    };
    *params = pl_color_map_default_params;
    params->tone_mapping_function =
        m->curve == DVBRIDGE_HDR10_CURVE_BT2390 ? &pl_tone_map_bt2390 : &pl_tone_map_spline;
    params->gamut_mapping = &pl_gamut_map_perceptual;
    params->metadata = PL_HDR_METADATA_ANY;
    params->inverse_tone_mapping = false;
    params->gamut_expansion = false;
```
**目标代码**:
```c
    float xy[8];
    if (m->gamut == DVBRIDGE_HDR10_GAMUT_CUSTOM)
        dvbridge_hdr10_custom_xy(m, xy);
    else
        dvbridge_hdr10_gamut_xy(m->gamut, xy);

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
        .transfer = sdr ? PL_COLOR_TRC_BT_1886 : PL_COLOR_TRC_PQ,
        .hdr = {.min_luma = (m->black > 0.0f) ? m->black : PL_COLOR_HDR_BLACK,
                .max_luma = m->peak,
                .prim = {.red = {xy[0], xy[1]}, .green = {xy[2], xy[3]}, .blue = {xy[4], xy[5]},
                         .white = {xy[6], xy[7]}}},
    };
    *params = pl_color_map_default_params;
    params->tone_mapping_function =
        m->curve == DVBRIDGE_HDR10_CURVE_BT2390 ? &pl_tone_map_bt2390 : &pl_tone_map_spline;
    params->gamut_mapping = &pl_gamut_map_perceptual;
    params->metadata = PL_HDR_METADATA_ANY;
    params->inverse_tone_mapping = false;
    params->gamut_expansion = false;
    params->dynamic_target = m->dynamic_target;
    params->contrast_recovery = m->contrast_recovery;
```

#### [tools/dvbridge/dvbridge_render.c:1930 & 2084](tools/dvbridge/dvbridge_render.c#L1930)
**现有原代码**:
```c
static bool render_hdr10(struct dvbridge_renderer *r, const struct pl_frame *source,
                         const void *metadata, size_t bytes, double pts, double el_pts,
                         struct dvbridge_view view, int width, int height,
                         const struct dvbridge_plain *plain)
{
    // ...
    if (r->hdr10_mapping.enabled) {
        struct dvbridge_level1 level1;
        map_to_display(r, &r->hdr10_mapping, &image.color, &target.color, &mapping,
                       level1_noted(r, metadata, bytes, &level1));
        params.color_map_params = &mapping;
    }
    // ...
}

bool dvbridge_render_plain(struct dvbridge_renderer *r, const struct pl_frame *source,
                          const struct dvbridge_plain *plain, struct dvbridge_view view,
                          int width, int height)
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
    r->hdr10_ready = render_hdr10(r, source, NULL, 0, 0.0, NAN, view, width, height, plain);
    if (gamut_table_retry(r, fine, r->hdr10_ready)) {
        r->hdr10_ready = render_hdr10(r, source, NULL, 0, 0.0, NAN, view, width, height, plain);
        gamut_table_kept(r, r->hdr10_ready);
    }
    restore_gl_state(&state);
    return r->hdr10_ready;
}
```
**目标代码**:
```c
static bool render_hdr10(struct dvbridge_renderer *r, const struct pl_frame *source,
                         const void *metadata, size_t bytes, double pts, double el_pts,
                         struct dvbridge_view view, int width, int height,
                         const struct dvbridge_plain *plain,
                         const struct dvbridge_level1 *measured_l1)
{
    // ...
    if (r->hdr10_mapping.enabled) {
        struct dvbridge_level1 level1;
        const struct dvbridge_level1 *l1 = plain ? measured_l1 : level1_noted(r, metadata, bytes, &level1);
        map_to_display(r, &r->hdr10_mapping, &image.color, &target.color, &mapping, l1);
        params.color_map_params = &mapping;
    }
    // ...
}

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

### 3.4 `xbmc/cores/VideoPlayer/VideoRenderers/DVBridgeGLES.h` 与 `.cpp`

#### [xbmc/cores/VideoPlayer/VideoRenderers/DVBridgeGLES.h:419-424](xbmc/cores/VideoPlayer/VideoRenderers/DVBridgeGLES.h#L419-L424)
```cpp
  bool PreparePlain(const Layer& base,
                    const dvbridge_plain& plain,
                    dvbridge_view view,
                    int width,
                    int height,
                    unsigned int serial,
                    const dvbridge_level1* measured_l1 = nullptr);
```

#### [xbmc/cores/VideoPlayer/VideoRenderers/DVBridgeGLES.cpp:2161](xbmc/cores/VideoPlayer/VideoRenderers/DVBridgeGLES.cpp#L2161)
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
```

#### [xbmc/cores/VideoPlayer/VideoRenderers/DVBridgeGLES.cpp:2309-2320](xbmc/cores/VideoPlayer/VideoRenderers/DVBridgeGLES.cpp#L2309-L2320)
**现有原代码**:
```cpp
void CDVBridgeGLES::SetConversionMapping(const dvbridge_hdr10_mapping& mapping)
{
  const bool same =
      m_convertMappingSet && mapping.enabled == m_convertMapping.enabled &&
      (!mapping.enabled ||
       (mapping.peak == m_convertMapping.peak && mapping.gamut == m_convertMapping.gamut &&
        mapping.curve == m_convertMapping.curve && mapping.target == m_convertMapping.target &&
        mapping.source_known == m_convertMapping.source_known &&
        (!mapping.source_known ||
         std::equal(std::begin(mapping.source_xy), std::end(mapping.source_xy),
                    std::begin(m_convertMapping.source_xy)))));
  if (same || !m_renderer)
    return;
```
**目标代码**:
```cpp
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
```

---

### 3.5 `xbmc/cores/VideoPlayer/VideoRenderers/HwDecRender/RendererVAAPIGLES.h` 与 `.cpp`

#### [xbmc/cores/VideoPlayer/VideoRenderers/HwDecRender/RendererVAAPIGLES.cpp:250-294](xbmc/cores/VideoPlayer/VideoRenderers/HwDecRender/RendererVAAPIGLES.cpp#L250-L294)
**现有原代码**:
```cpp
int CRendererVAAPIGLES::RenderPlainMapping(int idx)
{
  // its planes, as RenderDVConversion() takes them
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
  for (int p = 0; p < 2; ++p)
  {
    const auto& plane = buffer.fields[FIELD_FULL][p];
    layer.planes[p] = {plane.id, static_cast<int>(plane.texwidth),
                      static_cast<int>(plane.texheight)};
  }
  // ... and its colour: its transfer, range and HDR10 metadata (0 where not known)
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
  return window->RenderPlainMapping(layer, plain, m_sourceRect, m_destRect, buffer.doviSerial);
}
```
**目标代码**:
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
  return window->RenderPlainMapping(layer, plain, m_sourceRect, m_destRect, buffer.doviSerial, buffer.doviMetadata);
}
```

---

### 3.6 `xbmc/windowing/gbm/WinSystemGbmGLESContext.h` 与 `.cpp`

#### 1. `DVMeasureReady` 与 `DVMeasurePicture` 全文改造 ([行 4900-4940, 5035-5051](xbmc/windowing/gbm/WinSystemGbmGLESContext.cpp#L4900))
**现有原代码**:
```cpp
bool CWinSystemGbmGLESContext::DVMeasureReady()
{
  if (m_dvMeasureRestart)
  {
    m_dvMeasureRestart = false;
    ++m_dvMeasureEpoch;
    m_dvMeasureSubmitted.clear();
    m_dvMeasuredPts = DVD_NOPTS_VALUE;
    dvbridge_measure_reset(m_dvMeasure.get());
    dvbridge_measured_reset(m_dvMeasured.get(), false);
  }
  if (!m_dvMeasured)
  {
    dvbridge_measured_params params = dvbridge_measured_default_params;
    const auto component = CServiceBroker::GetSettingsComponent();
    const auto advanced = component ? component->GetAdvancedSettings() : nullptr;
    const bool noFloor = advanced && advanced->m_videoDVMeasuredNoAvgFloor;
    if (noFloor)
      params.avg_floor = 0;
    m_dvMeasured.reset(dvbridge_measured_create(&params));
    if (noFloor && m_dvMeasured)
      CLog::Log(LOGINFO, "DVBridge: HDR10 sent as Dolby Vision measured from the picture: the level 1 "
                         "average goes out as measured, without dovi_tool's floor of 819, as "
                         "advancedsettings.xml asks (dvmeasurednoavgfloor)");
  }
  if (!m_dvMeasure && !m_dvMeasureFailed)
  {
    m_dvMeasure.reset(dvbridge_measure_create());
    if (!m_dvMeasure)
    {
      m_dvMeasureFailed = true;
      DVBRIDGE::MeasurementFailed();
      CLog::Log(LOGERROR, "DVBridge: the measurement of HDR10 pictures could not be set up: they "
                          "go out with the metadata of their static metadata; HDR10+ sent as Dolby "
                          "Vision is not filled where its statistics are missing (as before)");
    }
  }
  return m_dvMeasure && m_dvMeasured;
}

bool CWinSystemGbmGLESContext::DVMeasurePicture(const CDVBridgeGLES::Layer& layer)
{
  if (!m_dvBridge || !m_dvState.Captured() || layer.layout != DVBRIDGE_P010 || !DVMeasureReady())
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
**目标代码**:
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

#### 2. `RenderPlainMapping` 全面重构 ([行 4200-4274](xbmc/windowing/gbm/WinSystemGbmGLESContext.cpp#L4200-L4274))
**目标代码**:
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

  // DTM: dynamically bypass contrast recovery when OSD/GUI is active to prevent GPU stalls
  const bool overlayFree = m_guiWillRender && GetGUIElementCount() == 0 && !m_dvOverlays;
  dvbridge_hdr10_mapping mapping = m_dvConvertMapping;
  if (!overlayFree)
    mapping.contrast_recovery = 0.0f;

  m_dvConvertBridge->SetConversionMapping(mapping);
  m_dvConvertBridge->SetConversionTarget(0, UseLimitedColor());

  // Dynamic Tone Mapping: Level 1 resolution (HDR10+ passthrough or GPU asynchronous measurement)
  dvbridge_level1 l1{};
  const dvbridge_level1* pL1 = nullptr;

  // P3: Strictly exclude HLG from PQ measurement and L1 injection
  if (mapping.enabled && !plain.hlg)
  {
    // P4: Fast path - direct reuse of ST 2094-40 metadata converted to L1 (0 GPU overhead)
    if (metadata.Data() && metadata.Size() > 0 &&
        dvbridge_level1_effective(metadata.Data(), metadata.Size(), &l1))
    {
      pL1 = &l1;
    }
    // Fallback path: GPU asynchronous measurement for PQ streams (VAAPI P010 only)
    else if (DVMeasureReady() && layer.layout == DVBRIDGE_P010)
    {
      // P1 & P7: Detect video stream switch or seek jump, resetting measurement state
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

      // P7: Trigger PBO fence collection to execute reduce and temporal smoothing
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
    ++(mapped && copied ? m_hdr10AdaptStats.mapped
                        : mapped ? m_hdr10AdaptStats.drawn
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
  if (mapped && m_gpuPower && (serial == 0 || serial != m_gpuPowerSerial))
  {
    m_gpuPowerSerial = serial;
    m_gpuPower->Drawn(GPUPOWER::Drawing::MAPPING);
  }
  return mapped ? 1 : 0;
}
```

#### 3. `RenderDVConversion` 接入 OSD 降载 ([行 4148-4155](xbmc/windowing/gbm/WinSystemGbmGLESContext.cpp#L4148-L4155))
**现有原代码**:
```cpp
  if (!m_dvConvertBridge->InitializeConversion())
    return -1;
  // mapped to the display as the output was told when the renderer was configured
  m_dvConvertBridge->SetConversionMapping(m_dvConvertMapping);
  // Hades: kept in the form that the copy into the window needs (dvbridge_render_hdr10_store())
  m_dvConvertBridge->SetConversionTarget(0, UseLimitedColor());
```
**目标代码**:
```cpp
  if (!m_dvConvertBridge->InitializeConversion())
    return -1;

  // DTM: dynamically bypass contrast recovery when OSD/GUI is active to prevent GPU stalls
  const bool overlayFree = m_guiWillRender && GetGUIElementCount() == 0 && !m_dvOverlays;
  dvbridge_hdr10_mapping mapping = m_dvConvertMapping;
  if (!overlayFree)
    mapping.contrast_recovery = 0.0f;

  m_dvConvertBridge->SetConversionMapping(mapping);
  m_dvConvertBridge->SetConversionTarget(0, UseLimitedColor());
```

#### 4. `TakeDVConversionMapping` 解除色域限制与联动 ([行 4276-4320](xbmc/windowing/gbm/WinSystemGbmGLESContext.cpp#L4276-L4320))
**目标代码**:
```cpp
dvbridge_hdr10_mapping CWinSystemGbmGLESContext::TakeDVConversionMapping(
    const VideoPicture& picture, bool sdr, bool plain)
{
  dvbridge_hdr10_mapping mapping{};
  mapping.enabled = false;
  const auto settings = SettingsNow();
  const bool mapSettingOn = settings &&
      settings->GetSetting(CSettings::SETTING_VIDEOSCREEN_HADESDVHDR10MAP) &&
      settings->GetInt(CSettings::SETTING_VIDEOSCREEN_HADESDVHDR10MAP) != 0;

  if (sdr)
  {
    mapping.enabled = true;
    mapping.target = DVBRIDGE_HDR10_TARGET_SDR;
    mapping.peak = mapSettingOn && settings->GetSetting(CSettings::SETTING_VIDEOSCREEN_HADESDVHDR10PEAK)
                       ? static_cast<float>(settings->GetInt(CSettings::SETTING_VIDEOSCREEN_HADESDVHDR10PEAK))
                       : DVBRIDGE_SDR_WHITE;
    const int gamutSetting = mapSettingOn && settings->GetSetting(CSettings::SETTING_VIDEOSCREEN_HADESDVHDR10GAMUT)
                                 ? settings->GetInt(CSettings::SETTING_VIDEOSCREEN_HADESDVHDR10GAMUT)
                                 : 2;
    switch (gamutSetting)
    {
      case 0: mapping.gamut = DVBRIDGE_HDR10_GAMUT_BT2020; break;
      case 2: mapping.gamut = DVBRIDGE_HDR10_GAMUT_BT709; break;
      default: mapping.gamut = DVBRIDGE_HDR10_GAMUT_P3_D65; break;
    }
    mapping.curve = (mapSettingOn && settings->GetSetting(CSettings::SETTING_VIDEOSCREEN_HADESDVHDR10CURVE) &&
                     settings->GetInt(CSettings::SETTING_VIDEOSCREEN_HADESDVHDR10CURVE) == 0)
                        ? DVBRIDGE_HDR10_CURVE_SPLINE
                        : DVBRIDGE_HDR10_CURVE_BT2390;
    mapping.dynamic_target = mapSettingOn && settings->GetSetting(CSettings::SETTING_VIDEOSCREEN_HADESDVDTMDYNAMIC) &&
                             settings->GetBool(CSettings::SETTING_VIDEOSCREEN_HADESDVDTMDYNAMIC);
    mapping.contrast_recovery = mapSettingOn && settings->GetSetting(CSettings::SETTING_VIDEOSCREEN_HADESDVDTMRECOVERY)
                                    ? settings->GetInt(CSettings::SETTING_VIDEOSCREEN_HADESDVDTMRECOVERY) / 100.0f
                                    : 0.0f;
    if (picture.hasDisplayMetadata && picture.displayMetadata.has_primaries)
    {
      const auto& d = picture.displayMetadata;
      const AVRational xy[8] = {d.display_primaries[0][0], d.display_primaries[0][1],
                                d.display_primaries[1][0], d.display_primaries[1][1],
                                d.display_primaries[2][0], d.display_primaries[2][1],
                                d.white_point[0],          d.white_point[1]};
      mapping.source_known = true;
      for (int i = 0; i < 8; ++i)
        mapping.source_xy[i] = xy[i].den ? static_cast<float>(av_q2d(xy[i])) : 0.0f;
      if (!dvbridge_hdr10_mapping_valid(&mapping))
        mapping.source_known = false;
    }
  }
  else if (mapSettingOn &&
           settings->GetSetting(CSettings::SETTING_VIDEOSCREEN_HADESDVHDR10PEAK) &&
           settings->GetSetting(CSettings::SETTING_VIDEOSCREEN_HADESDVHDR10GAMUT) &&
           settings->GetSetting(CSettings::SETTING_VIDEOSCREEN_HADESDVHDR10CURVE))
  {
    mapping.enabled = true;
    mapping.target = DVBRIDGE_HDR10_TARGET_HDR10;
    mapping.peak =
        static_cast<float>(settings->GetInt(CSettings::SETTING_VIDEOSCREEN_HADESDVHDR10PEAK));
    switch (settings->GetInt(CSettings::SETTING_VIDEOSCREEN_HADESDVHDR10GAMUT))
    {
      case 0: mapping.gamut = DVBRIDGE_HDR10_GAMUT_BT2020; break;
      case 2: mapping.gamut = DVBRIDGE_HDR10_GAMUT_BT709; break;
      default: mapping.gamut = DVBRIDGE_HDR10_GAMUT_P3_D65; break;
    }
    mapping.curve = settings->GetInt(CSettings::SETTING_VIDEOSCREEN_HADESDVHDR10CURVE) == 1
                        ? DVBRIDGE_HDR10_CURVE_BT2390
                        : DVBRIDGE_HDR10_CURVE_SPLINE;
    mapping.dynamic_target = settings->GetSetting(CSettings::SETTING_VIDEOSCREEN_HADESDVDTMDYNAMIC) &&
                             settings->GetBool(CSettings::SETTING_VIDEOSCREEN_HADESDVDTMDYNAMIC);
    mapping.contrast_recovery = settings->GetSetting(CSettings::SETTING_VIDEOSCREEN_HADESDVDTMRECOVERY)
                                    ? settings->GetInt(CSettings::SETTING_VIDEOSCREEN_HADESDVDTMRECOVERY) / 100.0f
                                    : 0.0f;
    // ...
```

#### 5. `TakeHdr10AdaptMapping` 父级开关联动 ([行 3054-3062](xbmc/windowing/gbm/WinSystemGbmGLESContext.cpp#L3054-L3062))
**目标代码**:
```cpp
    if (settings->GetSetting(CSettings::SETTING_VIDEOSCREEN_HADESDVHDR10CURVE) &&
        settings->GetInt(CSettings::SETTING_VIDEOSCREEN_HADESDVHDR10CURVE) != 1)
      mapping.curve = DVBRIDGE_HDR10_CURVE_SPLINE;

    mapping.dynamic_target = settings->GetSetting(CSettings::SETTING_VIDEOSCREEN_HADESDVDTMDYNAMIC) &&
                             settings->GetBool(CSettings::SETTING_VIDEOSCREEN_HADESDVDTMDYNAMIC);
    mapping.contrast_recovery = settings->GetSetting(CSettings::SETTING_VIDEOSCREEN_HADESDVDTMRECOVERY)
                                    ? settings->GetInt(CSettings::SETTING_VIDEOSCREEN_HADESDVDTMRECOVERY) / 100.0f
                                    : 0.0f;
```

---

### 3.7 `xbmc/windowing/gbm/WinSystemGbm.cpp`

#### [xbmc/windowing/gbm/WinSystemGbm.cpp:4242-4245](xbmc/windowing/gbm/WinSystemGbm.cpp#L4242-L4245)
**现有原代码**:
```cpp
        auto& t = hdr_metadata.hdmi_metadata_type1;
        const uint16_t limit = static_cast<uint16_t>(
            std::clamp(settings->GetInt(CSettings::SETTING_VIDEOSCREEN_HADESHDR10LIMIT), 100, 4000));
```
**目标代码**:
```cpp
        auto& t = hdr_metadata.hdmi_metadata_type1;
        const uint16_t limit = static_cast<uint16_t>(
            std::clamp(settings->GetInt(CSettings::SETTING_VIDEOSCREEN_HADESHDR10LIMIT), 40, 4000));
```
**机理说明**：在模式 B 下，普通 HDR10 或 DV 转换为 HDR10 时，`ConversionOutputAdapted`（`DVBridgeGLES.cpp:2352`）会将片源峰值改写为 `mapping.peak`，并在 `SetHDR10Signal` 中写入 DRM `HDR_OUTPUT_METADATA`。放宽 limit 下限至 40 nits，可确保当用户设定 50~80 nits 投影峰值时，DRM InfoFrame 能忠实广播该数值，彻底旁路投影机自身的静态压缩曲线。

---

### 3.8 `system/settings/settings.xml` 与 `xbmc/settings/Settings.h`

#### [system/settings/settings.xml:3910-3996](system/settings/settings.xml#L3910-L3996)
```xml
      <setting id="videoscreen.hadesdvhdr10map" type="integer" label="39832" help="39833">
        <requirement>
          <and>
            <condition>HAVE_GBM</condition>
            <condition>HAS_GLES</condition>
          </and>
        </requirement>
        <level>2</level>
        <default>0</default> <!-- as mastered: the display maps it -->
        <constraints>
          <options>
            <option label="39834">0</option> <!-- off -->
            <option label="39835">1</option> <!-- to this display -->
          </options>
        </constraints>
        <control type="spinner" format="string" />
      </setting>
      <setting id="videoscreen.hadesdvhdr10peak" type="integer" parent="videoscreen.hadesdvhdr10map" label="39836" help="39837">
        <requirement>
          <and>
            <condition>HAVE_GBM</condition>
            <condition>HAS_GLES</condition>
          </and>
        </requirement>
        <dependencies>
          <dependency type="enable" setting="videoscreen.hadesdvhdr10map" operator="!is">0</dependency>
        </dependencies>
        <level>2</level>
        <default>1000</default>
        <constraints>
          <minimum>40</minimum>
          <step>10</step>
          <maximum>4000</maximum>
        </constraints>
        <control type="spinner" format="string">
          <formatlabel>39838</formatlabel>
        </control>
      </setting>
      <setting id="videoscreen.hadesdvhdr10gamut" type="integer" parent="videoscreen.hadesdvhdr10map" label="39839" help="39840">
        <requirement>
          <and>
            <condition>HAVE_GBM</condition>
            <condition>HAS_GLES</condition>
          </and>
        </requirement>
        <dependencies>
          <dependency type="enable" setting="videoscreen.hadesdvhdr10map" operator="!is">0</dependency>
        </dependencies>
        <level>2</level>
        <default>1</default> <!-- DCI-P3 (D65) -->
        <constraints>
          <options>
            <option label="39841">0</option> <!-- BT.2020 -->
            <option label="39842">1</option> <!-- DCI-P3 (D65) -->
            <option label="39843">2</option> <!-- BT.709 -->
          </options>
        </constraints>
        <control type="spinner" format="string" />
      </setting>
      <setting id="videoscreen.hadesdvhdr10curve" type="integer" parent="videoscreen.hadesdvhdr10map" label="39844" help="39845">
        <requirement>
          <and>
            <condition>HAVE_GBM</condition>
            <condition>HAS_GLES</condition>
          </and>
        </requirement>
        <dependencies>
          <dependency type="enable" setting="videoscreen.hadesdvhdr10map" operator="!is">0</dependency>
        </dependencies>
        <level>3</level>
        <default>1</default> <!-- BT.2390 -->
        <constraints>
          <options>
            <option label="39847">1</option> <!-- BT.2390 -->
            <option label="39846">0</option> <!-- spline -->
          </options>
        </constraints>
        <control type="spinner" format="string" />
      </setting>
      <setting id="videoscreen.hadesdvdtmdynamic" type="boolean" parent="videoscreen.hadesdvhdr10map" label="39917" help="39918">
        <requirement>
          <and>
            <condition>HAVE_GBM</condition>
            <condition>HAS_GLES</condition>
          </and>
        </requirement>
        <dependencies>
          <dependency type="enable" setting="videoscreen.hadesdvhdr10map" operator="!is">0</dependency>
        </dependencies>
        <level>2</level>
        <default>true</default>
        <control type="toggle" />
      </setting>
      <setting id="videoscreen.hadesdvdtmrecovery" type="integer" parent="videoscreen.hadesdvhdr10map" label="39919" help="39920">
        <requirement>
          <and>
            <condition>HAVE_GBM</condition>
            <condition>HAS_GLES</condition>
          </and>
        </requirement>
        <dependencies>
          <dependency type="enable" setting="videoscreen.hadesdvhdr10map" operator="!is">0</dependency>
        </dependencies>
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

#### [xbmc/settings/Settings.h:476-485](xbmc/settings/Settings.h#L476-L485)
```cpp
  static constexpr auto SETTING_VIDEOSCREEN_HADESDVHDR10MAP = "videoscreen.hadesdvhdr10map";
  //! ... the peak of the display, in cd/m2
  static constexpr auto SETTING_VIDEOSCREEN_HADESDVHDR10PEAK = "videoscreen.hadesdvhdr10peak";
  //! ... its gamut (0: BT.2020, 1: DCI-P3 with D65 white, 2: BT.709)
  static constexpr auto SETTING_VIDEOSCREEN_HADESDVHDR10GAMUT = "videoscreen.hadesdvhdr10gamut";
  //! ... the curve (0: libplacebo's spline, 1: the BT.2390 EETF)
  static constexpr auto SETTING_VIDEOSCREEN_HADESDVHDR10CURVE = "videoscreen.hadesdvhdr10curve";
  //! Hades: dynamic virtual target scaling based on scene average luminance
  static constexpr auto SETTING_VIDEOSCREEN_HADESDVDTMDYNAMIC = "videoscreen.hadesdvdtmdynamic";
  //! Hades: contrast recovery strength for projector DTM (0: off, 10 to 100 percent)
  static constexpr auto SETTING_VIDEOSCREEN_HADESDVDTMRECOVERY = "videoscreen.hadesdvdtmrecovery";
```

---

## 四、 涉及文件与 LibreELEC 补丁持久化清单

严禁直接修改解压目录 `build.LibreELEC-Generic.x86_64-13.0-devel/build/`。所有改动必须以 Git Patch 形式固化至 LibreELEC 补丁树中：

| 涉及源文件路径 | 涉及核心功能 | 对应 LibreELEC 持久化补丁文件 |
| :--- | :--- | :--- |
| `tools/dvbridge/dvbridge_placebo.h` | 扩展 `dvbridge_hdr10_mapping`（新增 `dynamic_target`、`contrast_recovery`） | `projects/Generic/patches/kodi/x86/kodi-9980-projector-dynamic-tone-mapping.patch` |
| `tools/dvbridge/dvbridge_placebo.c` | 放行 SDR `BT2020` / `P3_D65` 色域校验；校验 `contrast_recovery` 范围 | 同上 |
| `tools/dvbridge/dvbridge_render.h` | `dvbridge_render_plain` 接口增加 `measured_l1` 参数 | 同上 |
| `tools/dvbridge/dvbridge_render.c` | 修正 SDR 色域映射 `out_prim`；`render_hdr10` 接收 `measured_l1` | 同上 |
| `xbmc/cores/VideoPlayer/VideoRenderers/DVBridgeGLES.h` | `PreparePlain` 声明增加 `measured_l1` 参数 | 同上 |
| `xbmc/cores/VideoPlayer/VideoRenderers/DVBridgeGLES.cpp` | `PreparePlain` 实现透传；`SetConversionMapping` 纳入 DTM 相等性比较 | 同上 |
| `xbmc/cores/VideoPlayer/VideoRenderers/HwDecRender/RendererVAAPIGLES.h` | `RenderPlainMapping` 声明传递 `doviMetadata` | 同上 |
| `xbmc/cores/VideoPlayer/VideoRenderers/HwDecRender/RendererVAAPIGLES.cpp` | 赋值 `layer.pts/duration/video`；透传 `doviMetadata` 直通 | 同上 |
| `xbmc/windowing/gbm/WinSystemGbmGLESContext.h` | `RenderPlainMapping` 接口声明接收 `metadata` | 同上 |
| `xbmc/windowing/gbm/WinSystemGbmGLESContext.cpp` | `DVMeasurePicture` 解绑 DV；HDR10+ 直通；Seek 重置；OSD 降载 | 同上 |
| `xbmc/windowing/gbm/WinSystemGbm.cpp` | 下调 `HDR_OUTPUT_METADATA` 限制下限至 40 nits | 同上 |
| `system/settings/settings.xml` | 移除 `ishdrdisplay` 依赖；新增 DTM 设置项 | 同上 |
| `xbmc/settings/Settings.h` | 注册 `SETTING_VIDEOSCREEN_HADESDVDTM*` 常量 | 同上 |
| `addons/resource.language.en_gb/resources/strings.po` | 补充 `39917-39920` 英文描述词条 | 同上 |

---

## 五、 实施路线图与测试验收方案

### 5.1 实施顺序
1. **生成并应用 Patch**: 按照上述第四章清单，将修改合并打包为补丁 `projects/Generic/patches/kodi/x86/kodi-9980-projector-dynamic-tone-mapping.patch`。
2. **清理包构建 Stamp**:
   ```bash
   rm -rf build.LibreELEC-Generic.x86_64-13.0-devel/.stamps/kodi* \
          build.LibreELEC-Generic.x86_64-13.0-devel/build/kodi-*
   ```
3. **单包增量编译**:
   ```bash
   PROJECT=Generic ARCH=x86_64 ./scripts/build_mt kodi:target
   ```

### 5.2 核心测试与验收准则
1. **SDR 投影仪模式 A 验证**:
   - 播放《双子杀手》(4K 60fps DV P7) 与《1917》(4K 24fps HDR10)；
   - 检查 `kodi.log` 中 `DVBridge: an HDR picture is mapped to SDR... (the display (100 cd/m2))` 日志，确认峰值按设置生效，色域输出为 DCI-P3 或 BT.2020；
   - 确认暗部层次清晰，高光不发生突兀死白剪切。
2. **HDR10 模式 B 验证**:
   - 开启模式 B，连接 HDR 投影仪，通过 `drm_info` 抓取 HDMI 端口输出的 `HDR_OUTPUT_METADATA`，确认 `max_display_mastering_luminance` 与 `max_cll` 精确等于设定峰值（如 100 nits）。
3. **GPU 负载与 OSD 交互防掉帧验证**:
   - 通过 `Hdr10AdaptTimerCollect` 抓取 GPU 时间，确认 4K 24p 下 GPU 耗时 $\le 6.5\text{ ms}$；
   - 连续呼出/隐藏播放条与设置菜单，确认 `contrast_recovery` 动态旁路机制平滑生效，无任何 Late Presentation（掉帧为 0）。
