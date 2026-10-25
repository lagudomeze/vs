# 反馈闭环

## 玩家入口

- 游戏内 **F3**：先把诊断（seed/daily/版本/窗口）复制到剪贴板，再打开 GitHub 反馈表单；粘贴即可。
- 试玩表单：.github/ISSUE_TEMPLATE/playtest_session.yml
- 直接链接：https://github.com/lagudomeze/vs/issues/new?template=playtest_session.yml
- Bug 表单（可选）：.github/ISSUE_TEMPLATE/feedback.yml

试玩表单固定收集：

- 版本（vx --version / commit）
- seed / 楼层 / 回合
- 职业、最远层数
- 平台（Windows / Deck）、输入设备、时长
- 总体评分 1–5
- 哪些做得好、哪里困惑、Bug、最想改的一件事
- 存档/截图（可选）

## 处理节奏

1. 每周固定时间过一遍新反馈，标 P0/P1/P2。
2. P0（崩溃/丢档/卡死）当天修，发 patch。
3. P1（玩法/平衡/UI 阻断）进下一个迭代。
4. P2（建议/观感）进 backlog，月度复盘。
5. 修复后在 issue 回复版本号与改动，关闭前确认复现步骤。

## Playtest 脚本

- 前 10 分钟：是否理解移动/瞄准/天赋？是否打开过背包/商店/祭坛？
- 首个 Boss：是否知道敌方意图和范围？死亡后是否愿意重开？
- 30 分钟：是否形成 Build 选择？金币是否够用？难度是否陡？
- 结束问卷：
  - 最有趣/最挫败的瞬间；
  - 最想改的一件事；
  - 是否愿意推荐给朋友（1–5）。

## 指标

- 首 Boss 到达率、通关率、平均回合；
- 职业分布、商店/祭坛使用率；
- 重开率、退款窗口内退出点；
- 反馈 issue 的 P0/P1 关闭时间。

不引入侵入式遥测；优先用 playtest 问卷、Steam 评论/论坛、Discord 反馈。
