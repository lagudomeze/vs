# 发行就绪度（第 155 轮）

状态：内部评估，不是发行承诺。日期 2026-10-25。

## 总览

| 领域 | 状态 | 证据 | 阻塞 |
| --- | --- | --- | --- |
| 核心循环 | 绿 | 3 职业/3 层/回合/永久死亡；QA normal 65.3% / hard 39.0% / easy 89.7% | 无 |
| 存档 | 绿 | v3、三代 .bak、1 MiB、fuzz | 云冲突未实测 |
| 3×3 地图 | 黄 | 已实现/存档/minimap；默认 OFF | 自然试玩数据 |
| Demo 代码 | 绿 | 单层/单职业/独立存档/结束页 | 独立 App/Depot |
| 商店素材 | 黄 | 7 张 1920 截图 + capsule + 30s 真实引擎 capture 预告片 | 正式手绘 key art、人手实机/正式配乐 |
| 音频 | 黄 | 程序化 SFX/ambience/victory | 未实机试听 |
| 本地化 | 黄 | English beta 覆盖菜单/HUD/商店/面板/常见战斗日志；461 去重字符串仍在审计 | 完整英文化/长文本验收 |
| Playtest | 红 | 0 名真实玩家 | 招募/反馈 |
| Steam 后台 | 红 | 无 AppID/DepotID/SDK；清单见 STEAM_BACKEND.md | 账号/费用/审核 |
| Deck | 黄 | 静态预检 0 fail；自动 2×；手柄可完成主要流程 | 无实机/Proton 验证 |
| 预告片 | 黄 | 30s capture 版（2.5s 标题 + 25s auto-bot gameplay + 2.5s 结束卡）+ 29.5s 原片 | 人手实机/正式配乐/人工剪辑 |
| 法务/许可 | 绿 | CC0/OFL/字体/隐私说明 | 正式发行前复核 |

## 不能对外宣称

- 不能称 "Steam Deck Verified"
- 不能称 "完整英文支持"（English beta 可写）
- 不能称 "预告片已完成"（只有 auto-bot 引擎内录屏）
- 不能称 "已有真实试玩好评"
- 不能称 "已上架 Steam"

## 下一阶段优先级

1. **5 名真实 Playtest + 记录**（最高）
2. **英文 UI 最小层**（影响海外）
3. **正式 key art/capsule + 30–60s MP4**
4. **Steam AppID/DepotID + SDK + Cloud**
5. **Deck/Proton 实机**

## 代码健康

- zig build test 264
- test-qa 145
- test-qa3 248
- PREFLIGHT PASS
- 开放 issue：#123/#122/#121/#120/#115
- 无开放 PR；main 干净

## 结论

代码与单机内容已接近可试玩；**发行准备仍缺真实玩家、正式美术、英文和 Steam 后台**。下一步应先做 Playtest，而不是继续堆功能。
