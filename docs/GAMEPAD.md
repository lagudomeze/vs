# 手柄 / Steam Input

## 当前映射

SDL3 Gamepad，启动时打开第一个已连接手柄。

| 输入 | 功能 |
| --- | --- |
| D-pad / 左摇杆 | 移动（按方向触发一次） |
| A (South) | 确认 / 等待（等同 Space） |
| B (East) | 取消 / 关闭面板 / Esc |
| X (West) | 背包 |
| Y (North) | 角色 |
| LB | 天赋 1 |
| RB | 天赋 2 |
| 左摇杆按下 | 天赋 3 |
| Start | 帮助 |
| Back | 设置 |

Steam Input 可把手柄映射成标准 XInput 布局；不需要额外配置即可被 SDL 识别。

## 实现

- SDL_InitSubSystem(SDL_INIT_GAMEPAD)
- SDL_GetGamepads + SDL_OpenGamepad
- 每帧轮询按钮/轴，按边缘触发
- 左摇杆死区 16000，方向变化才发一步

## 限制

- 支持 GAMEPAD_ADDED/REMOVED 热插拔，始终使用第一个可用手柄。
- 没有震动/扳机/右摇杆视角。
- 没有改键 UI。
- 手柄提示尚未画在 HUD 上，先写 README/本文件。

## 验证

- 编译器/单测覆盖 API 调用；实机需 Steam Deck 或 XInput 手柄。
- 若手柄未连接，全部逻辑跳过，键鼠不受影响。
