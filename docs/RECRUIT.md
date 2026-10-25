# Playtest 招募与渠道

状态：招募方案；尚未发布招募帖，也还没有真实测试者数据。

目标：5–10 名喜欢回合制 Roguelike/地牢爬行的玩家，完成 20–30 分钟、到第 2 层、留下一条具体反馈。

## 1. 目标玩家

优先：

- 玩过 ToME、Slay the Spire、Caves of Qud、DCSS、Into the Breach
- 接受永久死亡与像素/低多边形画面
- 愿意用键盘或 Xbox 布局手柄，能接受 30 分钟不跳过对话

不优先：

- 只玩动作/联机游戏
- 要求联机/云存档/Steam 成就
- 只想拿 key 不测试

## 2. 渠道（按优先级）

| 渠道 | 做法 | 注意 |
| --- | --- | --- |
| 个人好友/群 | 1 对 1 发 zip + 30 分钟预约 | 不群发，不拉无关的人 |
| Discord Roguelike 社区 | 先问管理员，再发 #playtest 频道 | 遵守频道规则；不重复刷 |
| Reddit r/roguelikes | 用 Self-Promotion 日/周规则，附截图与明确请求 | 先读置顶；不私信轰炸 |
| itch.io devlog | 发短 devlog + 招募表 | 不在别人的页面打广告 |
| 本地 gamedev meetup | 现场 2–3 台机器 | 同意书/记录表 |
| Steam 社区 | 有商店页后再发 Playtest 公告 | 不承诺未实现功能 |

不做：

- 买评论/刷愿望单
- 用免费 key 换好评
- 未经同意录屏/录音
- 把测试者原话当营销素材（除非单独授权）

## 3. 英文招募帖模板

> **Playtesters wanted: turn-based pixel dungeon crawl (30 min, Windows)**
>
> I am testing VX: Aether Keep, a single-hero turn-based roguelike. Three classes, three floors, visible enemy intents, permanent death. It is an early build: no multiplayer, no cloud saves, no achievements yet.
>
> I need 5–10 people who like turn-based roguelikes to play for 20–30 minutes and tell me where they got stuck. You get a zip, no installer; keyboard or Xbox-style gamepad both work. I will not record you or collect personal data; notes are anonymous and you can ask me to delete them.
>
> If you are interested, reply/DM and I will send the build + the structured playtest form: https://github.com/lagudomeze/vs/issues/new?template=playtest_session.yml
>
> Please do not share the build outside the test.

## 4. 中文招募帖模板

> **求 5–10 名回合制 Roguelike 测试者（30 分钟，Windows）**
>
> 我在测试《VX: Aether Keep》：单英雄、回合制、像素地牢，三职业三层，敌人意图可见，永久死亡。早期版本，暂无联机/云存档/成就。
>
> 想找喜欢回合制 Roguelike 的玩家玩 20–30 分钟，重点告诉我哪里卡住、哪里看不懂。解压即玩，不录屏、不收集个人信息，笔记匿名，可要求删除。
>
> 有兴趣请回复/私信，我发测试包和 4 个问题。请不要外传测试包。

## 5. 筛选问题

1. 最近玩过的 2 款回合制/Roguelike 游戏？
2. 能接受永久死亡吗？用键盘还是手柄？
3. 本周能否抽出 30 分钟、用 Windows 运行 zip？
4. 是否同意匿名记录：版本/种子/职业/层数/死亡原因/原话反馈？
5. 是否同意在测试后填写结构化反馈表（playtest_session.yml）？

## 6. 排期

- 先约 3 人做 pilot，修 P0/P1
- 再约 5–7 人，避免同一 bug 重复浪费
- 每场间隔至少 30 分钟，留记录时间
- 同一天不超过 3 场

## 7. 记录

使用 [playtest_tracker.csv](playtest_tracker.csv)。每场结束 10 分钟内填完；P0/P1 立即开 issue。

## 8. 成功标准

- 5–10 人完成
- ≥60% 到第 2 层
- ≥50% 愿意再开一局
- 严重 UX 阻塞 ≤1 人
- 0 崩溃/坏档
- 至少 3 条可执行改动进入 issue

## 9. 隐私

- 只记录昵称/编号，不记录真实姓名、邮箱、IP
- 不默认上传遥测；F4 诊断由玩家手动粘贴
- 测试者可随时要求删除笔记
- 公开引用原话前单独征求同意
