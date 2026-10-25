# 发行就绪度（第 100 轮）

状态：内部评估，不是发行承诺。日期 2026-10-25。

## 总览

| 领域 | 状态 | 证据 | 阻塞 |
| --- | --- | --- | --- |
| 核心循环 | 绿 | 3 职业/3 层/回合/永久死亡；QA 63.3% normal | 无 |
| 存档 | 绿 | v3、三代 .bak、1 MiB、fuzz | 云冲突未实测 |
| 3×3 地图 | 黄 | 已实现/存档/minimap；默认 OFF | 自然试玩数据 |
| Demo 代码 | 绿 | 单层/单职业/独立存档/结束页 | 独立 App/Depot |
| 商店素材 | 黄 | 程序化占位截图/capsule/分镜 | 正式手绘/MP4 |
| 音频 | 黄 | 程序化 SFX/ambience/victory | 未实机试听 |
| 本地化 | 黄 | English beta 覆盖 10+ 屏；仍有回退中文 | 完整英文化/验收 |
| Playtest | 红 | 0 名真实玩家 | 招募/反馈 |
| Steam 后台 | 红 | 无 AppID/DepotID/SDK；清单见 STEAM_BACKEND.md | 账号/费用/审核 |
| Deck | 黄 | 静态预检 0 fail；自动 2× | 无实机 |
| 预告片 | 黄 | 20s 分镜板 | 无 MP4/音频 |
| 法务/许可 | 绿 | CC0/OFL/字体/隐私说明 | 正式发行前复核 |

## 不能对外宣称

- 不能称 "Steam Deck Verified"
- 不能称 "完整英文支持"（English beta 可写）
- 不能称 "预告片已完成"
- 不能称 "已有真实试玩好评"
- 不能称 "已上架 Steam"

## 下一阶段优先级

1. **5 名真实 Playtest + 记录**（最高）
2. **英文 UI 最小层**（影响海外）
3. **正式 key art/capsule + 30–60s MP4**
4. **Steam AppID/DepotID + SDK + Cloud**
5. **Deck/Proton 实机**

## 代码健康

- zig build test 230
- test-qa 143
- test-qa3 218
- 开放 issue：#123/#122/#121/#120/#115
- 无开放 PR；main 干净

## 结论

代码与单机内容已接近可试玩；**发行准备仍缺真实玩家、正式美术、英文和 Steam 后台**。下一步应先做 Playtest，而不是继续堆功能。
