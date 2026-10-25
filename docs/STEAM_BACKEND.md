# Steam 后台准备清单

状态：模板与商店素材已存在，**没有真实 AppID/DepotID/SDK**。不要编造 ID。

## 0. 实际提交顺序（没有 AppID 时）

1. 注册 Steamworks 合作伙伴，支付 100 USD/app 费用（可回收，按 Valve 当前条款）。
2. 完成税务/银行信息。
3. 后台创建正式 App；Demo 单独创建 App，不复用正式 AppID。
4. 取得 AppID/DepotID，填 steam/app_build.vdf 与 depot_build.vdf。
5. 上传 build，设置 launch option，先在 Steam 客户端跑一遍。
6. 商店页先上 Coming Soon（至少提前 2 周），再排 build review。
7. Demo 走独立 review；Playtest 可用 Playtest App 或 keys。
8. 价格/日期未定，不在文档/页面写死。

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

## 5. 商店素材（当前实际文件）

- header_capsule_920x430.png
- small_capsule_462x174.png
- main_capsule_1232x706.png
- vertical_capsule_748x1084.png + 374x542
- library_capsule_600x900.png + 300x450
- library_hero_3840x1240.png
- library_logo_1280x720.png
- page_background_1438x810.png
- community_icon_184x184.png
- 7× 1920×1080 screenshots（screenshots_1920/）
- trailer_capture_30s.mp4（auto-bot 实机 capture 版）
- 商店文案（中英，docs/store/PAGE.md）
- 系统需求 / 无障碍 / 隐私说明 / 反馈表单
- 正式 key art 仍是占位，上架前替换
- AI 生成内容披露：按实际素材来源填写，不猜

## 6. 成就/统计（可选，未接）

本地徽章：FIRST WIN / ALL CLASSES / FLAWLESS / CHUNK HUNTER / DAILY DELVER。接 Steam 时映射为 Stat/Achievement，不改变单机逻辑。

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

- 没有 AppID/DepotID（未支付/未创建）
- 没有 Steamworks SDK/overlay/成就接入
- key art/capsule 仍是程序化占位
- 预告片是 auto-bot capture，不是人手实机/正式配乐
- 没有真实 Playtest 反馈
- 没有 Deck/Proton 实机验证
