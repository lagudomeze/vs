# Steam 发行与反馈计划

> 目标：把当前可玩 demo 变成可上架、可被玩家反馈驱动迭代的 Steam 产品。  
> 事实依据：Steamworks 官方文档（见文末）。价格/日期类信息以官方页面为准，本文给的是执行清单。

## 1. 现在缺什么

| 类别 | 现状 | 上架前必须做 |
| --- | --- | --- |
| 账号/费用 | 无 Steamworks 后台 | 注册 Steamworks，支付 100 USD/产品；等待 30 天 |
| 商店页 | 无 Coming Soon | 提前至少 2 周公开 Coming Soon |
| 构建 | 已加 --version / package.ps1 / SteamPipe 模板 | SteamPipe appid、depot、启动项 |
| Steam 集成 | Auto-Cloud 路径已配；无 SDK | SteamAPI_Init、Overlay、成就（可选） |
| 存档路径 | 已改 SDL_GetPrefPath；旧 saves 自动迁移；--portable 保留 cwd | Cloud 白名单 |
| 声音 | 程序化 SFX + 环境音 + 单声部 motif | 多轨编曲/更多环境层 |
| 设置 | 全屏/窗口/VSync/倍率/音量已可调 | 键位、语言、音频设备 |
| 手柄 | SDL3 gamepad 基础映射 + 热插拔 | 改键、Steam Input 官方配置 |
| 本地化 | 中文 | 英文商店页 + 英文本地化（至少 UI/日志） |
| 商店素材 | 占位 Capsule + 1920 截图已生成 | 正式 key art、5 张截图、预告片 |
| 法律 | 无 | EULA/隐私政策、第三方许可（SDL/zflecs/字体/Kenney） |
| 反馈 | 已有 F3 GitHub 表单 | Discord/Steam 论坛、Demo 问卷 |

## 2. 发行阶段

### Phase 0：可发行构建（2–3 周）

- 存档改到用户可写目录；旧 saves/ 做迁移。
- 加设置面板：全屏、3×/2× 缩放、主音量/音效、键位提示。
- 统一版本号/窗口标题/图标；--version。
- Windows x64 ReleaseFast 打包脚本：exe + 依赖 + 许可文件。
- 崩溃/错误日志落盘；启动失败给出可读提示。
- QA：不同 DPI、双屏、只读安装目录、无音频设备、存档损坏。

### Phase 1：Steamworks 接入（1–2 周）

- Steamworks SDK，steam_appid.txt 仅开发用；发布构建不打包该文件。
- 启动时 SteamAPI_Init，失败可离线启动。
- Steam Cloud 同步存档（先做单文件/槽位白名单）。
- 成就：首胜、三职业通关、无伤 Boss、全祭坛等，按实际内容定。
- Rich Presence 可选。
- Steam Deck：Proton 下 640×360 3× 窗口/全屏验证。

### Phase 2：商店页与 Demo（3–4 周）

- Coming Soon 页至少提前 2 周；越早越好，先积累愿望单。
- 占位生成：docs/store/README.md + tools/store_assets.py；正式美术替换。
- 素材：
  - Header capsule 920×430
  - Small capsule 462×174
  - Main capsule 1232×706
  - Vertical capsule 748×1084
  - Library capsule 600×900
  - 至少 5 张 1920×1080 截图（16:9）
  - 30–60 秒预告片
- 文案：一句话卖点、3–5 个卖点、中文/英文。
- Demo：前 2 层 + 1 个 Boss，存档独立，约 20–30 分钟。
- 申请 Steam Playtest 或外部 demo key。

### Phase 3：反馈与 Next Fest（4–8 周）

- 20–50 人 playtest：观察前 10 分钟、死亡楼层、职业选择、是否用商店/祭坛。
- 反馈渠道：Discord、Steam 论坛、游戏内“反馈”按钮（打开链接）。
- 指标（本地/问卷，不做侵入式遥测）：
  - 首个 Boss 到达率、通关率、平均回合、重开率；
  - 职业分布、商店购买率、祭坛使用率；
  - 退款窗口内退出点。
- 每周固定 patch；把高频反馈转成 issue，标注 P0/P1/P2。
- Next Fest 前准备 demo + 直播切片 + 媒体 key。

### Phase 4：发售

- 用 steam/app_build.vdf.example + depot_build.vdf.example 上传（先填 AppID/DepotID）。
- 提交 build review（预留至少 1–2 周）。
- 发售折扣建议 10–15%，不要长期深折。
- 发售首周每天看评论/论坛，热修优先崩溃/存档/卡死。
- 发售后 30 天不做低于首发折扣的促销（Steam 折扣冷却规则）。

## 3. 定价与定位

- 建议先按“短篇 roguelike demo → 完整版”验证，不先承诺大体量。
- 价格区间建议 8.99–12.99 USD（待 playtest 内容量验证）；国区按 Steam 建议汇率。
- 卖点优先级：3D 像素地牢、可旋转俯视、三职业、Boss 多阶段、Build 组合。
- 避免宣传“ToME 复刻”；用“经典 roguelike 启发”描述。

## 4. 团队分工（当前一人多角色，按可委派粒度拆）

| 角色 | 这轮之后的活 |
| --- | --- |
| 主设计/架构 | 版本范围、Steam 页文案、issue 优先级 |
| 程序 A | 存档路径、设置、Steamworks、Cloud |
| 程序 B | 手柄/Steam Input、成就、打包脚本 |
| 美术 | Capsule、截图、预告片、图标 |
| QA | 安装目录/DPI/Deck/坏档/离线 |
| UX 批评 | 前 10 分钟、设置可发现性、死亡反馈 |

## 5. 当前内容风险

- 无音频：商店页和试玩第一印象会明显吃亏。
- 只有中文：英文商店页/UI 是愿望单转化的硬门槛。
- 难度曲线：普通 65.3%、困难 40%；demo 需要更平滑的前 20 分钟。
- 存档路径/只读目录：不修会在部分玩家机器上直接丢档。
- 没有设置：全屏/音量/缩放缺失会被差评。
- 没有成就/Cloud：不是 blocker，但影响 Steam 原生体验。

## 6. 官方参考

- Steam Direct fee / 30-day wait: https://partner.steamgames.com/steamdirect
- Release options / Coming Soon ≥2 weeks: https://partner.steamgames.com/doc/store/types
- Graphical assets: https://partner.steamgames.com/doc/store/assets
- Library assets: https://partner.steamgames.com/doc/store/assets/libraryassets
- Uploading / SteamPipe: https://partner.steamgames.com/doc/sdk/uploading
- Steamworks SDK: https://partner.steamgames.com/doc/sdk
- Steam Cloud: https://partner.steamgames.com/doc/features/cloud
