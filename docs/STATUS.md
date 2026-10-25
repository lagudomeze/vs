# 项目状态 / 责任矩阵

快照：main c31462c（2026-10-25）。没有外部团队；"负责人"是当前会话承担的角色帽子，不是虚构的人。

## P0

无。没有已知崩溃/坏档/无法启动。

当前验证：263/145/247；PREFLIGHT PASS；IRONWOOD HEART 后 QA normal 65.7%。

## P1

| Issue | 标签 | 负责人帽子 | 状态 | 下一步 | 阻塞 |
| --- | --- | --- | --- | --- | --- |
| #122 | area:steam / priority:p1 / help wanted | Design + Community | Playtest 包、商店文案、表单就绪；0 名真实测试者 | 招募 3–5 人，按 playtest_session.yml 记录 | 需要真人，不能编数据 |
| #121 | area:steam / priority:p1 / blocked:external | Release | 包/SteamPipe 预检/一键 gate 通过 | 注册 Steamworks、交 100 USD、拿 AppID/DepotID | 账号、税/银行、费用 |

## P2

| Issue | 标签 | 负责人帽子 | 状态 | 下一步 | 阻塞 |
| --- | --- | --- | --- | --- | --- |
| #123 | area:input / priority:p2 | UI/Input | 默认手柄、A/B swap、全屏、设置、首次引导、鼠标职业/暂停/商店/祭坛/角色/背包已可用 | Steam Input 官方映射、手柄重绑定、Deck 实机 | 无硬阻塞；Deck 实机未测 |
| #120 | area:engine / priority:p2 | Engine | ECS 仅渲染 scene graph；反射受阻于 zflecs 命名/脚本 | 等上游或写 C shim | 技术阻塞，非产品阻塞 |
| #115 | area:gameplay / priority:p2 | Gameplay | 时空法师反馈/状态时长已加；架构重构未做 | 先收集实际试玩反馈再定 | 反馈不足 |

## 本周只做三件

1. 发出 3 份 Playtest 包，收回 3 份结构化记录（#122）。
2. 创建 Steamworks 账号并确认税务/银行（#121）。
3. 用 DECK_CHECK 的 15 分钟脚本跑一次真机/Proton（#123）。

## 不做

- 不伪造愿望单/好评/试玩人数。
- 不在没有 AppID 时假装已上架。
- 不在没有硬件时宣称 Deck Verified。
