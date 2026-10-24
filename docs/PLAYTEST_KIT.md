# Playtest 工具包

状态：脚本可用；测试包在 dist/playtest/，不进版本库。

## 生成

~~~powershell
zig build -Doptimize=ReleaseFast
pwsh -File tools/package.ps1
pwsh -File tools/playtest_pack.ps1
~~~

产物：dist/playtest/vx-playtest-<version>.zip

## 内容

| 文件 | 用途 |
| --- | --- |
| vx.exe + runtime | 解压即玩 |
| PLAYTEST_README.txt | 启动/F2/F3/F4/存档/无遥测说明 |
| CONSENT.txt | 自愿、匿名、可删除的简明同意 |
| FEEDBACK.md | 单人记录模板 + P0–P3 分级 |
| README/CREDITS/OFL | 项目说明与字体许可 |

## 招募

渠道、英文/中文文案、筛选问题、排期与隐私见 [RECRUIT.md](RECRUIT.md)；记录用 [playtest_tracker.csv](playtest_tracker.csv)。

## 分发

- 只发 zip，不发源码/开发构建
- 附一句测试目标：30 分钟、到第 2 层、记录卡住点
- 不收集账号/真实姓名；不默认录屏
- 测试结束让玩家决定笔记是否保留

## 主持流程

1. 解压到可写目录，双击 vx.exe
2. 不解释，观察前 5 分钟
3. 卡住 60 秒才提示
4. 结束前按 F4，粘贴诊断到 FEEDBACK.md
5. 按 [PLAYTEST.md](PLAYTEST.md) 做访谈与归档

## 验收

- [ ] zip 内 vx.exe 可启动
- [ ] 说明包含 F2/F3/F4 与存档路径
- [ ] 不包含 steam_appid.txt
- [ ] 不含开发者本机存档
- [ ] 体积 < 10 MB

## 当前状态

已生成 vx-playtest-0.1.0.zip（约 2.6 MB），内容清单已核对。尚未招募真实测试者。
