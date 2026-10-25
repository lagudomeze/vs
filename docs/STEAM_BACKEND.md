# Steam 后台准备清单

状态：模板已存在，**没有真实 AppID/DepotID/SDK**。不要编造 ID。

## 1. 需要 Valve 后台创建

- 正式版 AppID
- Demo AppID（独立，不共用正式版）
- 正式版 DepotID
- Demo DepotID
- 商店包（Store Package）
- Beta 包（可选）
- Steamworks SDK 访问权限

## 2. SteamPipe 模板

现有 [steam/app_build.vdf](../steam/app_build.vdf) 是占位。填：

- AppID
- DepotID
- contentroot
- buildoutput
- Launch option：vx.exe，工作目录根
- Demo：独立 App/Depot，Launch Arguments 加 --demo
- 不要把 steam_appid.txt 打进包

## 3. 启动参数

| 场景 | Executable | Arguments |
| --- | --- | --- |
| 正式版 | vx.exe | 空 |
| Demo | vx.exe | --demo |
| 调试窗口 | vx.exe | --scale 2 |
| 强制英文 | vx.exe | --lang en |

## 4. Auto-Cloud

建议 root：saves

同步：

- *.save
- records.json

不同步：

- .bak/.bak2/.bak3
- 截图
- 日志/诊断

冲突：优先 Steam 客户端冲突 UI；本地保留三代备份。Demo 独立目录 vx/demo，不与正式版混。

## 5. 商店素材

- 616×353 capsule
- 920×430 header
- 1920×1080 screenshots
- 30–60s MP4 trailer
- 商店文案（中英）
- 系统需求
- 隐私说明/反馈渠道
- AI 生成内容披露（如有）

## 6. 成就/统计（可选，未接）

本地徽章：FIRST WIN / ALL CLASSES / FLAWLESS / CHUNK HUNTER。接 Steam 时映射为 Stat/Achievement，不改变单机逻辑。

## 7. 测试矩阵

- Windows 10/11
- 1280×800（Deck 模式）
- 1920×1080
- 无手柄/手柄
- 中文/English beta
- 新档/旧档/损坏档
- 云同步两台机器

## 8. 不能做

- 不能填假 AppID
- 不能把正式版 AppID 写进 Demo
- 不能在未实机验证时宣称 Deck Verified
- 不能把 English beta 标成完整英文支持

## 9. 当前阻塞

- 没有 AppID/DepotID
- 没有 Steamworks SDK 接入
- 没有真实商店素材/预告片
- 没有真实 Playtest
