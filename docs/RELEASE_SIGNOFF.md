# 发布签核（v0.1.0 / 2026-10-25）

## 结论

| 目标 | 状态 | 依据 |
| --- | --- | --- |
| 内部/好友 Playtest 包 | **READY** | 266/145/250；全量/Demo 包可运行；存档隔离 |
| Steam 商店正式版 | **NOT READY** | 无 AppID/DepotID/SDK；key art/预告仍是占位级 |

不要把当前包当作 Steam 正式版上传。可以发给试玩者，但必须说明是 early build。

## 证据

- commit：d25ecf2
- 全量包：dist/vx-0.1.0-win64.zip
- 全量 SHA256：A62206148625BB5F89F1624D6DAF6474A49CFC7C979E9BDD01416B05C4EA7EC4
- Demo 包：dist/demo/vx-demo-0.1.0.zip
- Demo SHA256：17F7FEA8C78DFC7BA5B74827D06EAACD70CD77E063C3C174760A2E8648F3A4B5
- release_gate：-SkipPreflight 实跑 exit 0（playtest/press/steam_check/package_check + 三个 SHA）
- preflight：PASS（-SkipPackage；fmt/三层测试/Deck 静态/i18n/截图）
- steam_check：exit 0，SteamPipe-ready（AppID/DepotID 待填）
- steam_package_check：PASS，仅 YOUR_APP_ID/YOUR_DEPOT_ID 警告
- Demo 冒烟：解包运行 exit 0，HP 184，存档在 %APPDATA%/lagudomeze/vx/demo
- 干净解包冒烟：全量/Demo version=vx 0.1.0，headless exit 0，无 steam_appid，无本地 saves。
- 包内容：全量/Playtest 均含 CHANGELOG.md，README 为 266/266，vx 0.1.0 可运行。



## 可对外说

- 3 职业、3 层、回合制、永久死亡、每日挑战、手柄可玩
- 7 张 1920 截图、30s auto-bot capture 预告
- English beta（非完整本地化）

## 不可对外说

- Steam Deck Verified
- 完整英文支持
- 正式预告片/正式配乐已完成
- 已有真实玩家好评/愿望单数据
- 已上架 Steam

## 正式发行前必须清

1. Steamworks 账号 + 100 USD + 税务/银行
2. 正式 AppID/DepotID，填 vdf，上传 build
3. 正式 key art/capsule（当前程序化占位）
4. 人手实机 capture + 正式音频
5. 5–10 名真实 Playtest 反馈并修 P0/P1
6. Deck/Proton 实机（至少一个 Proton 版本）
7. Store 页/语言表/系统需求/隐私与反馈渠道复核
