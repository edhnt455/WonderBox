# 上游合并验证

## 2026-11-07：合并 v1.2.4

- 当前分支：`main`，合并前为 `bd0d5a6`。
- 合并来源：`upstream/main`，`dcb5790`（v1.2.4），包含 2 个新提交。
- 接入概览页整机功耗卡片、独立菜单栏功耗开关及上游文档和截图。
- 保留定制版 `1.3.0 / 130`、CPU/RAM 占用配色及上下排列；功耗加入同一布局，以普通文字颜色显示瓦数。原隐藏图标设置的存储键不变，文案改为“只显示数值”，支持仅开启功耗时隐藏图标。
- README 区分当前定制版和上游发行版，说明截图与定制布局的差异。

### 验证结果

- `git diff --cached --check`：通过；无未解决冲突。
- `python3 -m unittest discover -s Tests/Packaging -v`：7 项通过。
- `swift test`：编译成功；352 项测试，10 项跳过，1 项失败。
- 菜单栏 17 项测试及概览功耗 3 项测试全部通过，覆盖三项数值开关、瓦数边界、睡眠唤醒、颜色渲染、仅功耗时隐藏图标及概览布局。
- 设置界面渲染测试通过；检查生成的 PNG，四个开关和说明文字完整显示。
- 字符串目录 JSON 校验及 Swift 中文翻译覆盖测试通过。上次记录的 `sync_localization.py --check` 字符串提取问题本次未修复、未重跑；不宣称该检查通过。
- 唯一失败仍为上次记录的 `PowerTests.testFirstPowerSamplePrimesAnEnergyBaselineWhenHostSupportsCPU`。主机仍为 macOS 27.0.1（26A434）；该测试及生产功耗采样器与上游完全相同，原因见下方历史记录中的说明。未通过修改上游功耗策略规避失败。

本次未执行安装、打包发布或远程推送。

## 2026-11-06：合并 v1.2.3

- 当前分支：`main`，合并前为 `2dc536b`。
- 合并来源：`upstream/main`，`783a2ad`（v1.2.3），包含 3 个新提交。
- 冲突处理：保留定制版 `1.3.0 / 130`；README 发布链接更新到上游 v1.2.3；保留菜单栏 CPU/RAM 配色、上下排列和隐藏应用图标功能。

## 验证结果

- `git diff --cached --check`：通过，无未解决冲突。
- `python3 -m unittest discover -s Tests/Packaging -v`：7 项通过。
- `swift test`：编译成功；345 项测试，10 项跳过，1 项失败。
- 唯一失败项：`PowerTests.testFirstPowerSamplePrimesAnEnergyBaselineWhenHostSupportsCPU`。当前主机运行 macOS 27.0.1（26A434）。测试的能力探测使用 `PowerClassifier.readings` 默认的 `allowLegacyCPU: true`，而生产采样器在 macOS 27 上明确禁用旧 CPU 能量回退；因此测试探测到旧计数器后要求生产采样器提供 CPU 值，断言失败。相关测试、采样器和分类器保持上游实现，未为通过测试修改功耗策略。
- `python3 scripts/sync_localization.py --check`：构建成功，但报告大量既有字符串为 stale，返回 1；从检查结果看，编译器字符串提取没有得到预期键集合，原因尚未验证。此脚本未修改字符串目录；Swift 测试中的中文覆盖检查通过。当前工具链为 Apple Swift 6.4。

合并完成不代表全部验证通过。上述功耗测试和本地化提取检查仍需后续处理；未执行打包发布、安装或远程推送。
