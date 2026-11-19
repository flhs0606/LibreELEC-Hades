# kodi-diag eval 在 le 机上的翻页计数失效——问题分析与改进建议

日期: 2026-11-18
状态: 已实施并实机验证（2026-11-18，le 机 tf3 全协议通过；工具在
`~/.local/bin/kodi-diag`，仓库外）
关联: 本日 DV L5 三态实机验证（[2026-11-18-dv-l5-three-state-setting-design.md](2026-11-18-dv-l5-three-state-setting-design.md) §7）中首次确认；工作区耦合复查见 [2026-11-18-kodi-diag-skill-workspace-coupling-audit.md](2026-11-18-kodi-diag-skill-workspace-coupling-audit.md)

## 1. 现象

对 le 机（LibreELEC x86_64）执行 `kodi-diag eval le 20`，翻页与帧率两项永远为零：

```
* 屏幕实际呈现帧率 (Rendered FPS): 0.0 fps (0 次物理翻页)
* 物理翻页状态: ❌ 帧率过低或首帧假死
⚠️ 致命物理/时序缺陷:
  - ❌ 物理翻页完全停滞 (0 flips)，实机电视卡死在第一帧！(音频假装正常推进)
```

而播放实际完全健康。同一时刻 kodi.log 里 Kodi 自身的呈现统计（每 10 秒一条）：

```
DVBridge: last 10 s: 240 frames shown (0 of them keeping the picture on the
screen, ...), 0 not shown, ...; longest gap between shown frames 42.2 ms;
0 presentations over 1.5 refresh periods; ...
```

240 帧 / 10 s ≈ 23.976 fps（tf3 的帧率），0 未呈现、0 丢帧、A/V 漂移恒定。

## 2. 排查与证据

设备事实：le = 192.168.50.9，LibreELEC（x86_64，Linux 7.2），GPU 为
**Intel Alder Lake-N [UHD Graphics]**（`lspci` 00:02.0，DRM 仅 card0）。
**与显卡厂商无关**——工具并不读 dmesg，翻页数来自 kodi.log 文本计数。

工具实现（`~/.local/bin/kodi-diag`，翻页提取，约 :677-691）：

```python
# le（非 Amlogic）分支
dv_flips = log_delta.count("BeginDVBridge called:")
kms_flips = log_delta.count("FlipPage") + log_delta.count("FlipDVBridgePage")
flips = max(dv_flips, kms_flips)
rendered_fps = flips / duration_sec if duration_sec > 0 else 0.0
...
if metrics["flips"] == 0:            # :736
    failures.append("❌ 物理翻页完全停滞 (0 flips)，实机电视卡死在第一帧！...")
```

四条证据：

| # | 证据 | 结论 |
| :-- | :-- | :-- |
| 1 | `grep -rn "BeginDVBridge called" xbmc/` 在 Kodi 22.0rc2-Piers Hades 全源码中 **0 命中** | 模式串在当前代码里不存在，`dv_flips` 恒 0 |
| 2 | `FlipPage` / `FlipDVBridgePage` 仅作为函数名与调用出现（如 `WinSystemGbm.cpp:606`、`:2311`），无任何日志输出包含这两个词 | `kms_flips` 恒 0 |
| 3 | 这类行属 DEBUG 级，需 `debug.extralogging` 开启才进 kodi.log；工具的 `toggle_extralogging()`（:501-509）只由 `kodi-diag log <机型> on\|off`（:864）手动触发，**eval 从不开启** | 即使模式串正确，默认日志级别下也数不到 |
| 4 | 真实翻页证据始终存在于 **INFO 级** 行 `DVBridge: last 10 s: N frames shown (M not shown …)`（每 10 s 一条，无需任何开关；`LogDVStats("last 10 s")`，WinSystemGbmGLESContext.cpp:942/:10370/:10570） | 有零开销的替代数据源 |

被排除的错误归因：最初怀疑"NVIDIA 驱动不往 dmesg 记 flip 事件"——设备实为
Intel，且 kodi.log 里 VAAPI 行的 `with nvidia-vaapi-driver` 字样只是关于表面
数量节省的通用备注，不代表本机驱动。

## 3. 根因与影响

根因是**双重叠加**：(a) le 分支的计数模式串针对旧构建，在当前 Kodi 22 Hades
源码中不存在；(b) eval 不开启组件调试日志，DEBUG 级计数行本也不会出现。

影响：KPI 裁决 `rendered_fps >= 20` 在 le 机上**永远假 FAIL**，每次 eval 都打
"致命物理/时序缺陷"假警报。风险是狼来了效应——真出现翻页停滞时反而可能被当作
伪影放过；同时污染 kodi-diagnose 技能状态机的裁决分支（FAIL 会触发全栈抓日志
与因果假设流程，白白消耗 3 轮循环上限）。

## 4. 改进建议

### P0（必改）：le 分支翻页数据源换成 INFO 统计行

从增量日志解析 `DVBridge: last 10 s:` 行，而不是数 DEBUG 单帧行：

```python
import re
# 锚定 "last 10 s"：不得放宽为 "DVBridge:.*frames shown"——DV 输出结束时会冲刷
# 一条不定长窗口的 "DVBridge: until the end: N frames shown ..."（:5994），混入会污染分母
DV_10S = re.compile(r"DVBridge: last 10 s: (\d+) frames shown \((\d+) of them")
NOT_SHOWN = re.compile(r"(\d+) not shown")

shown = kept = not_shown = windows = 0
for line in log_delta.splitlines():
    m = DV_10S.search(line)
    if m:
        windows += 1
        shown += int(m.group(1))   # 含 kept 重复提交
        kept += int(m.group(2))    # group(2) 是 "of them keeping..."(kept)，不是 not shown
        n = NOT_SHOWN.search(line)
        if n:
            not_shown += int(n.group(1))

flips = shown                      # 每次 shown（含 kept 重复提交）即一次呈现（翻页）
rendered_fps = shown / (windows * 10) if windows else 0.0
```

要点：

- **评估窗口对齐**：10 s 锚点对齐播放启动相位而非评估窗——`eval 20` 的增量
  日志内必含恰好 2 条统计行，但覆盖区间为 [t1−10, t2]，最多向评估窗之前多含
  ~10 s、并在评估窗末尾留下最多 ~10 s 无覆盖。单窗整窗停滞仍会把均值拉到
  ~12 fps 触发 FAIL；评估窗末尾不足 10 s 的短停滞可能被稀释。评估秒数 < 10
  时可能一条都取不到，回退为"证据不足"而非 0（见 P1）。
- **输出标注来源**：结果行注明 `flips 来源: kodi.log DVBridge 10s 统计`，与
  Amlogic 机的 dmesg/DEBUG 来源区分，读报告时可知证据链。
- **适用前提**：统计行仅在 `m_dvSignalling` 置位期间出现（DV 输出，含 HDR10
  tunnel，WinSystemGbmGLESContext.cpp:794-804）；普通 SDR 播放永远没有。eval
  样本库为 DV/HDR 资产故成立；无证据时输出须区分三种原因——非 DVBridge 输出
  / 无任何呈现（疑似管线死亡）/ 模式串失配（见 P1）。
- 从同行取 `not shown`、`presentations over 1.5 refresh periods` 作交叉验证
  （现状的 underflow/丢帧项与 Kodi 统计互相独立，可对照）；其中
  `longest gap between shown frames` 建议直接纳入 P0——单窗最大间隙是带证据
  语义的最灵敏停滞检测，比平均 fps 更直接对应"冻结帧"判据。

### P1（建议）：证据缺失时 fail-open，并做模式串对齐校验

- `flips == 0` 且**没有任何可识别的证据行**时，判"翻页证据不可用（警告）"而
  不是"翻页停滞（致命）"——无法证明停滞就不应断言致命。只有当证据行存在且
  数值为 0/极低时才 FAIL。
- **fail-open 的边界**：`last 10 s` 行的 10 s 检查位于呈现路径内部
  （WinSystemGbmGLESContext.cpp:941/:10369），不呈现就不触发——渲染管线彻底
  死亡时一条统计行都没有，纯 fail-open 会把"音频活着/画面冻结"（本 KPI 原本
  要抓的场景）静默降级为警告。须叠加：eval 已知在播 DV 内容且 speeds/advancing
  健康而 `windows == 0` 时至少判 DEGRADED，并按 P0"适用前提"中三种无证据
  原因分流告警。
- 对 Amlogic 分支的 `AMLCodec::GetPicture` / `GetPicture -` 做同样的源码存在
  性核对（CE 21/22 各自的内核与 Kodi 版本），避免下次升级后再踩同一坑。落地
  形态：模式串集中成表并注明各自锚定的 Kodi 源码位置，配内嵌录制日志 fixture
  的 `--selftest`（工具在仓库外、无 CI，纯手工审计会再次腐烂）。
- 若确需 DEBUG 级单帧行做精细分析，由 eval 在开始时自动 `toggle_extralogging
  on`、结束时恢复（try/finally），但不作为 rendered_fps 的主数据源。

### P2（可选）：旁证与负向测试

- JSON-RPC `Player.GetProperties` 的 `percentage`/`time` 步进作播放推进旁证
  （已在 eval 中采样，只需在翻页异常时联动呈现）。
- 修复后验证协议：`kodi-diag eval le 20`（tf3，23.976fps）期望
  `rendered_fps ≈ 23.98 ± 0.5`、verdict PASS。
- 负向测试（审查修正）：暂停（speed=0）期间 `frames shown` 大概率**不会**
  低于 20 fps——"保持画面"路径 `KeepDVBridgeFrame()`
  （WinSystemGbmGLESContext.cpp:10236）对重复提交同样 `shown++; kept++`，由
  vblank 节拍驱动。暂停的正确签名是 `kept/shown` 占比趋近 1（活跃播放 ≈ 0，
  tf3 样例 240/0）；负向判据应先实测校准，或改用 kept 占比作暂停正/负控制。

## 5. 附录：实测样例行（2026-11-18 09:54:23.690，有删节）

> 注：折行为本文档排版所致；实际 kodi.log 中该统计为单行（CLog 不折行），
> 解析按单行匹配即可，勿将本附录直接复制为测试 fixture。

```
DVBridge: last 10 s: 240 frames shown (0 of them keeping the picture on the
screen, which was not drawn again), 0 not shown, 216 composed with GUI
elements; ...; longest gap between shown frames 42.1 ms; 0 presentations
over 1.5 refresh periods; 240 frames presented a frame ahead ...; the flips
came after the times that the player's clock called for their frames by
-29.7 ms (-29.7 to -29.6) over 240 frames ...
```

## 6. 实施记录（2026-11-18）

- **P0 已实施**：`_analyze_metrics` le 分支改为解析 `DVBridge: last 10 s:`
  统计行（shown/kept/not shown/单窗最大间隙），`flips = shown`、
  `rendered_fps = shown / (windows × 10)`；正则锚定 `last 10 s` 排除
  `until the end` 冲刷行；模式串集中成表（注明源码锚点），报告输出标注
  flips 来源（`kodi.log DVBridge 10s 统计 (INFO)`）。
- **P1 已实施（le）**：证据分流四态——`stats`（正常裁决：fps<20 FAIL、
  单窗间隙 >500 ms DEGRADED）/ `window-too-short`（警告）/ 
  `dv-active-no-stats`（DEGRADED，疑似模式串失配）/ `no-dv-output`
  （播放时钟健康时 DEGRADED，区分非 DV 内容与管线死亡）。不再对 0 flips
  无条件致命 FAIL。
- **P1 Amlogic 审计结果**：`AMLCodec::GetPicture` 仅函数名
  （AMLCodec.cpp:2661），`GetPicture -` 仅 DEBUG 级 eof 标记
  （DVDVideoCodecFFmpeg.cpp:876/893/900），均非逐帧行——ce 分支与 le 原患
  同一疾病（此前被 ce 机离线掩盖）。已同步改为"证据不可用（警告）"，
  INFO 级数据源待后续接入。
- **selftest 已实施**：`kodi-diag selftest` 内嵌实机 fixture（统计行、
  `until the end`、A/V 行），验证模式串、指标提取、证据分流与 KPI 裁决；
  Kodi 升级后先跑 selftest 再上实机。
- **P2 实机验证已通过（2026-11-18，le 机 tf3）**：
  - 播放中 `eval le 20`：`rendered_fps = 24.0`（480 帧翻转 / 2 窗口，
    期望 ≈23.98 ± 0.5 ✓）、verdict PASS、exit 0；旧"0 flips 假警报"消失。
  - 暂停（speed=0）校准：翻页仍 24.0 fps（`KeepDVBridgeFrame` 按 vblank
    持续重提交画面），FAIL 由 `speed==0` 正确触发——证实审查修正：暂停的
    负向判据是 **speed 与 kept 占比**，不是帧率。kept/shown 实测签名：
    播放中 0/240（0%）、过渡窗 29/240、暂停后 240/240（100%）。
  - 指标语义就此定型：`rendered_fps` 度量呈现管线存活（含 kept 重提交），
    内容推进由 `speed`/`advancing` 判定——两者职责分离。
- **待办**：ce 分支 INFO 级翻页数据源待接入（CE 机离线，暂无验证条件）。
