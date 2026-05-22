# CPU Thermal Watch

这是一个针对特定 Linux 笔记本平台问题的 `runtime workaround`。

## 解决什么问题

这台 `HP Laptop 14s-cr2xxx / Intel i7-10510U` 在 `Windows` 下能稳定跑到大约 `15W / 1.9GHz`，但在 `Ubuntu 24.04` 下即使停掉 `throttled`、切换 `6.17 HWE` 和 `6.8 GA` 内核，仍长期只有大约 `7.5W / 1.3GHz`，并持续出现 `power limit status=1`。

排查结果显示，性能瓶颈主要来自 Linux 的 `processor_thermal` 平台热管理链路，而不是 CPU 本体、风扇故障，或单纯的 `throttled` 配置。

## 这个软件是怎么做的

这个 watchdog service 会周期性读取 `x86_pkg_temp` 和 AC 状态，然后在两种运行模式之间切换：

- `fast` 模式：停掉 `thermald`，保持 `throttled` 停止，卸载 `processor_thermal` 相关模块链，以换取更高的 CPU sustained power。
- `safe` 模式：重新加载 `processor_thermal` 相关模块，并恢复 `thermald`，把系统带回更保守的热管理状态。

默认策略：

- 接电且包温 `<= 68°C`：进入 `fast`
- 包温 `>= 78°C`：回到 `safe`
- 电池模式：强制 `safe`
- 温度轮询：`1s`

## 为什么它比较特殊

这不是通用优化脚本，而是一个针对特定平台兼容问题的系统级 workaround。

- 它会在运行时卸载/重载内核模块
- 它会接管 `thermald`
- 它会保持 `throttled` 停止
- 它依赖 `systemd`

因此它更接近“平台行为修正”，不是普通的用户态调参工具。

## 已知效果

在这台机器上，短时重计算压测结果大致如下：

- 默认 Linux 状态：约 `7.6-7.8W / 1.3GHz`
- 只停 `throttled`：单核改善明显，但多核仍然偏低
- 卸载 `processor_thermal` 链后：约 `10W / 1.8GHz`

这仍然没有完全达到 Windows 下的 `15W`，但已经明显改善。

实际长时间使用中，这台机器后来稳定在大约 `67°C / 1.8GHz`，说明当前阈值和 `1s` 轮询在这台机器上至少是可用的。

## 为什么没有顺手去调 `psys / RAPL`

这个方案刻意没有把 `/sys/class/powercap` 里的 `psys` 限额也一起改掉。

原因是这台机器已经做过一次运行时 A/B：

- `fast` 模式基线：约 `10.17W / 1.82GHz`
- 临时把 `psys` 长期限额从 `15W` 提到 `20W` 后：约 `10.03W / 1.80GHz`

也就是说，在已经卸载 `processor_thermal` 链之后，继续抬 `psys` 并没有带来额外收益。

因此当前安装器只保留“切换平台热管理链”的最小有效策略，不额外去写 `RAPL`，避免把一个无效且更侵入的动作固化到系统里。

## 安装

本地执行：

```bash
bash ubuntu/cpu-thermal-watch/install.sh
```

如果需要自定义阈值：

```bash
bash ubuntu/cpu-thermal-watch/install.sh install \
  --high-temp 75 \
  --low-temp 65 \
  --poll-interval 1
```

## 查看状态

```bash
bash ubuntu/cpu-thermal-watch/install.sh status
```

也可以直接看：

```bash
cat /run/cpu-thermal-watch.mode
sudo journalctl -u cpu-thermal-watch.service -f
```

## 卸载

```bash
bash ubuntu/cpu-thermal-watch/install.sh uninstall
```

说明：

- 卸载后会删除 service、脚本和配置文件
- 卸载时会尝试重新启动 `thermald`
- `throttled` 不会自动重新启用，避免把原来的性能问题带回来

如果你确实想恢复它：

```bash
sudo systemctl enable --now throttled.service
```

## 注意点

- 这是面向 `Linux + Intel + systemd` 的方案，不保证适用于其他平台
- 建议只在接电使用
- 长时间高负载下的热行为仍需要你自己观察
- 这个方案目前主要改善的是 sustained power；如果想再进一步追频率，就已经进入更高风险的 `ACPI / kernel cmdline / platform thermal` 调整范围了
- 这不是 BIOS、EC 或硬件层面的真正修复，而是 Linux 侧的折中方案
- 如果将来换内核、换发行版、升级 BIOS 后问题消失，应该优先移除这个 workaround

## 相关文件

- 安装脚本：[`install.sh`](./install.sh)
- 系统脚本安装位置：`/usr/local/sbin/cpu-thermal-watch.sh`
- 系统配置安装位置：`/etc/default/cpu-thermal-watch`
- systemd service：`/etc/systemd/system/cpu-thermal-watch.service`
