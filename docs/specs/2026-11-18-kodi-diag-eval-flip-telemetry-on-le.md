# kodi-diag eval 在 le 机上的翻页计数失效——问题分析与改进建议

日期: 2026-11-18
状态: 待修（工具在 `~/.local/bin/kodi-diag`，仓库外；本文档为问题记录与改进方案）
关联: 本日 DV L5 三态实机验证（[2026-11-18-dv-l5-three-state-setting-design.md](2026-11-18-dv-l5-three-state-setting-design.md) §7）中首次确认

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
| 4 | 真实翻页证据始终存在于 **INFO 级** 行 `DVBridge: last 10 s: N frames shown (M not shown …)`（每 10 s 一条，无需任何开关） | 有零开销的替代数据源 |

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
DV_10S = re.compile(r"DVBridge: last 10 s: (\d+) frames shown \((\d+) of them")

shown = not_shown = windows = 0
for line in log_delta.splitlines():
    m = DV_10S.search(line)
    if m:
        windows += 1
        shown += int(m.group(1))
        not_shown += ...   # 需要时从 "N not shown" 再取一组

flips = shown                      # 一个 shown frame 即一次呈现（翻页）
rendered_fps = shown / (windows * 10) if windows else 0.0
```

要点：

- **评估窗口对齐**：该行每 10 s 一条，`eval 20` 恰好覆盖 2 个完整窗口；不足
  一个窗口时（评估秒数 < 10）回退为"证据不足"而非 0（见 P1）。
- **输出标注来源**：结果行注明 `flips 来源: kodi.log DVBridge 10s 统计`，与
  Amlogic 机的 dmesg/DEBUG 来源区分，读报告时可知证据链。
- 顺带可从同行取 `not shown`、`longest gap between shown frames`、
  `presentations over 1.5 refresh periods` 作为交叉验证指标（现状的
  underflow/丢帧项与 Kodi 统计互相独立，可对照）。

### P1（建议）：证据缺失时 fail-open，并做模式串对齐校验

- `flips == 0` 且**没有任何可识别的证据行**时，判"翻页证据不可用（警告）"而
  不是"翻页停滞（致命）"——无法证明停滞就不应断言致命。只有当证据行存在且
  数值为 0/极低时才 FAIL。
- 对 Amlogic 分支的 `AMLCodec::GetPicture` / `GetPicture -` 做同样的源码存在
  性核对（CE 21/22 各自的内核与 Kodi 版本），避免下次升级后再踩同一坑。
- 若确需 DEBUG 级单帧行做精细分析，由 eval 在开始时自动 `toggle_extralogging
  on`、结束时恢复（try/finally），但不作为 rendered_fps 的主数据源。

### P2（可选）：旁证与负向测试

- JSON-RPC `Player.GetProperties` 的 `percentage`/`time` 步进作播放推进旁证
  （已在 eval 中采样，只需在翻页异常时联动呈现）。
- 修复后验证协议：`kodi-diag eval le 20`（tf3，23.976fps）期望
  `rendered_fps ≈ 23.98 ± 0.5`、verdict PASS；可选负向测试：暂停播放
  （speed=0）时翻页应显著低于阈值，验证判据仍有效。

## 5. 附录：实测样例行（2026-11-18 09:54:23.690，有删节）

```
DVBridge: last 10 s: 240 frames shown (0 of them keeping the picture on the
screen, which was not drawn again), 0 not shown, 216 composed with GUI
elements; ...; longest gap between shown frames 42.1 ms; 0 presentations
over 1.5 refresh periods; 240 frames presented a frame ahead ...; the flips
came after the times that the player's clock called for their frames by
-29.7 ms (-29.7 to -29.6) over 240 frames ...
```
