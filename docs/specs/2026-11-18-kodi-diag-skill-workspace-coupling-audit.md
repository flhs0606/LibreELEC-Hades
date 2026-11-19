# kodi-diag skill 工作区耦合复查——残留缺陷与改进建议

日期: 2026-11-18
状态: 已落地（skill 在 `~/.config/opencode/skills/kodi-diagnose/SKILL.md`，工具在
`~/.local/bin/kodi-diag`，均在仓库外；P0/P1/P2 已于 2026-11-18 获批实施，
行为验证待下次"执行播放测试"触发时确认）
关联: [2026-11-18-kodi-diag-eval-flip-telemetry-on-le.md](2026-11-18-kodi-diag-eval-flip-telemetry-on-le.md)
（eval 翻页修复）；同日 deploy 二进制发现式 glob 修复（工具内
`KODI_BIN_GLOBS`，已实施）

## 1. 背景：工作区实况

`/home/mephis/Project/` 当前仅有两个工作区：

| 工作区 | 内容 | 机型代号 | 实机状态（2026-11-18） |
| :-- | :-- | :-- | :-- |
| `CoreELEC/`（内嵌 `coreelec` 仓库） | CE 21，Amlogic-ng.arm-21 构建树 | `ce-21` | 🔴 离线 |
| `LibreELEC-Hades/`（本仓库） | Kodi 22.0rc2-Piers Hades，Generic x86_64 | `le` | 🟢 在线 |
| ~~`CoreELEC-22/`~~ | 已删除 | `ce-22` | 🔴 离线 |
| ~~`libreelec-x86-DV/`~~ | 已删除 | — | — |

工具侧的工作区耦合已于同日修复：`find_kodi_bin()` 改为发现式 glob
（`KODI_BIN_GLOBS`，锚定 `build.<DISTRO>-<DEVICE>-<ARCH>-<VERSION>` 目录名，
按 mtime 取最新，与工作区名解耦）。skill（SKILL.md）未同步复查，本次补查。

## 2. 复查发现

### P0（必改）：机型推断映射双重失效，且会误路由到错误实机

SKILL.md §一.1 步骤 1（`SKILL.md:17`）：

> 根据工作区推断机型（`CoreELEC-22` -> `ce-22`；`libreelec-x86-DV` -> `le`；
> 其余 -> `ce-21`）

两个命名工作区均已删除，映射的兜底规则"其余 -> `ce-21`"现在会命中
**LibreELEC-Hades**：agent 在本仓库执行"执行播放测试"会把起播/清日志/
eval/deploy 全部发给 **ce-21（192.168.50.7，CoreELEC Amlogic 盒子）**——
测试对象完全错误；若走到 deploy，还会把 CE 21 的 kodi.bin 热替换进 CE 盒子，
污染不属于本轮验证的设备状态。这是主动误操作风险，不是静默失败。

### P1（建议）：设备表与速查的过时标注

- §三 表格 `le` 行标注 "LibreELEC (x86-DV / ...)"（`SKILL.md:65`）：
  `x86-DV` 是已删除的工作区名，现为 LibreELEC-Hades fork。
- §三 速查 `deploy <target>`（`SKILL.md:76`）未写可选 `[bin路径]` 参数——
  工具已支持显式指定（`~/.local/bin/kodi-diag:914`），多工作区并存或发现式
  glob 误选时需要它兜底；usage（`print_usage`）已写 `[bin]`，skill 与工具
  说明不一致。
- `ce-22` 行应加注：工作区已于 2026-11 删除，deploy 无二进制来源；实机
  离线。status/eval/log 流程保留，待工作区重建后恢复 deploy。

### P2（可选）：构建命令与仓库规约对齐

SKILL.md §一.1 步骤 e 写"仅增量编译单包：`scripts/build kodi:target`"
（`SKILL.md:27`）。两仓库 `scripts/build` 均存在，命令可用，但与
LibreELEC-Hades 的 [AGENTS.md](../../../AGENTS.md) 规约不一致：规约要求
`PROJECT=... ARCH=... ./scripts/build_mt <pkg>:target`（并行构建，失败日志在
`${BUILD}/.threads/logs/<pkg>.log`，避免串行重跑）。skill 指引 agent 走的
路径应与仓库规约一致，否则 agent 会选择无日志定位途径的串行构建。

## 3. 改进建议

### P0：机型推断改为"构建树特征"，与 deploy 修复同构

把"工作区文件夹名 → 机型"换成"当前目录构建树特征 → 机型"，与
`KODI_BIN_GLOBS` 同一哲学（构建目录名由 `PROJECT/DEVICE/ARCH/VERSION`
决定，天然抗工作区改名/迁移）：

```
自动识别标的：按当前工作区的构建树特征推断机型——
  存在 build.LibreELEC-Generic.x86_64-*  → le
  存在 build.CoreELEC-Amlogic-ng.arm-21  → ce-21
  存在 build.CoreELEC-*-aarch64-22 / Amlogic-no → ce-22（工作区待重建）
  无法推断时必须向用户询问机型，严禁默认兜底
```

最后一条是本次事故的教训：**推断失败应显式失败，而不是兜底到任意机型**。

### P1：表格与速查修正

- `le` 行标注改 `LibreELEC-Hades fork (x86_64 / Linux 7.2)`。
- `ce-22` 行加注"工作区已删（2026-11），deploy 不可用"。
- 速查行改 `kodi-diag deploy <target> [bin路径]`，注明默认按发现式 glob
  取最新构建产物、来源路径会打印在输出中。

### P2：构建命令对齐

步骤 e 改为 `PROJECT=<...> ARCH=<...> ./scripts/build_mt kodi:target`，
并注明失败时读 `${BUILD}/.threads/logs/kodi.log` 而非重跑。

## 4. 验证要点

- P0 落地后：在 LibreELEC-Hades 工作区触发"执行播放测试"，确认 agent 识别
  为 `le`（192.168.50.9）；在无构建树的目录触发时，确认 agent 询问而非
  兜底 `ce-21`。
- ce-22：`kodi-diag status ce-22` 离线属预期；`deploy ce-22` 应打印
  "工作区已删除"说明（工具侧已实现，`KODI_BIN_GLOBS` 无该键）。

## 5. 结论

工具（kodi-diag CLI）经同日修复后已无工作区名耦合；剩余风险全部集中在
SKILL.md 的三处：机型推断映射（P0，主动误操作风险）、过时标注（P1）、
构建命令与仓库规约不一致（P2）。SKILL.md 修改已于 2026-11-18 获批落地。
