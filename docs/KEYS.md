# 按键重绑（settings.json）

状态：配置文件级重绑。**没有按键捕获 UI**；修改后重启游戏生效。

文件：%APPDATA%\lagudomeze\vx\saves\settings.json（portable 模式为 ./saves/settings.json）

## 可重绑动作

数值是 SDL3 scancode，不是 ASCII。默认值：

| 字段 | 动作 | 默认 scancode | 默认键 |
| --- | --- | --- | --- |
| confirm | 确认/等待/施法 | 44 | SPACE |
| potion | 药水 | 19 | P |
| bomb | 炸弹 | 5 | B |
| inventory | 背包 | 12 | I |
| character | 角色 | 6 | C |
| talent1 | 天赋 1 | 30 | 1 |
| talent2 | 天赋 2 | 31 | 2 |
| talent3 | 天赋 3 | 32 | 3 |

移动键由 F2 第 7 项在 WASD / ESDF 间切换；方向键与小键盘始终可用。ESC（41）、F1–F12、数字 1–6 的菜单选择、R/Tab 等仍固定。

## 示例

~~~json
{
  "fullscreen": false,
  "scale": 3,
  "vsync": true,
  "volume": 0.55,
  "ambient": true,
  "pad_swap": false,
  "esdf": false,
  "keys": {
    "confirm": 44,
    "potion": 19,
    "bomb": 5,
    "inventory": 12,
    "character": 6,
    "talent1": 30,
    "talent2": 31,
    "talent3": 32
  }
}
~~~

## 规则

- 1 ≤ scancode ≤ 300；ESC(41) 会被拒绝并回退默认。
- 允许重复绑定，但同一键会同时触发多个动作，不推荐。
- 修改后重启游戏；设置面板 F2 的其他项会保存整个 keys 对象。
- 这是 v1 折中方案；按键捕获 UI/Steam Input 官方配置仍待做。

## 常见 scancode

A=4, B=5, C=6, D=7, E=8, F=9, G=10, H=11, I=12, J=13, K=14, L=15,
M=16, N=17, O=18, P=19, Q=20, R=21, S=22, T=23, U=24, V=25, W=26, X=27,
Y=28, Z=29, 1=30 … 9=38, 0=39, RETURN=40, ESC=41, SPACE=44,
F1=58 … F12=69.
