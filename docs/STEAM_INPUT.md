# Steam Input（模板，未接入）

状态：**只有 Action Manifest 模板**，当前构建仍用 SDL3 Gamepad。不要把它当成已接入 Steam Input。

文件：[steam/steam_input_manifest.vdf.example](../steam/steam_input_manifest.vdf.example)

## 动作映射

| 动作 | 类型 | 游戏内 |
| --- | --- | --- |
| move | joystick | 左摇杆/D-pad |
| confirm | button | 确认/等待/施法 |
| cancel | button | 取消/关闭 |
| inventory | button | 背包 |
| character | button | 角色 |
| talent1/2/3 | button | 三天赋 |
| wait | button | 原地等待 |

## 为什么没接

- 需要 Steamworks SDK 与 AppID
- 需要 SteamAPI_Init 成功后再调用 SteamInput()->SetActionManifestPath
- 需要每帧 GetDigitalActionData/GetAnalogActionData，替换或并行 SDL 映射
- 当前无 SDK 环境，接一个假接口会破坏无 Steam 构建

## 接入步骤（未来）

1. 把 .vdf.example 复制为 steam_input_manifest.vdf，放进构建产物。
2. 链接 Steamworks SDK，SteamAPI_Init 成功后设置 manifest 路径。
3. 获取 action set/handle，激活 gameplay。
4. 用 Steam Input 数据填充 FrameInput 的 move/confirm/...。
5. 保留 SDL fallback：无 Steam/无手柄时仍可玩。
6. 在 Steam Deck 上验证 A/B 布局、摇杆死区、热插拔。

## 验收

- [ ] 无 Steam 启动不崩溃
- [ ] Steam 启动时 manifest 加载成功
- [ ] 手柄/Steam Deck 可完成移动、攻击、药水、炸弹
- [ ] 键位提示与 A/B swap 一致
- [ ] 不与 SDL 映射双触发


## 预检

~~~powershell
pwsh -File tools/steam_input_check.ps1
~~~

检查：manifest 存在、括号平衡、9 个动作、英中本地化、steam_appid.txt 泄漏、STEAMWORKS_SDK、vx.exe。SDK 未设置只 WARN；模板未接入时 PASS。
