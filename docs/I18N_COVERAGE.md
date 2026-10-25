# 英文覆盖矩阵

状态：English beta，不是完整本地化。开启方式：--lang en 或 F2 -> L。

## 已验证截图

| 界面 | 状态 | 截图 |
| --- | --- | --- |
| 设置 | 完整 | settings_en.png |
| 主菜单/职业卡 | 完整 | menu_en.png |
| 游戏 HUD | 核心完整 | gameplay_en.png |
| 商店 | 完整 | shop_en.png |
| 祭坛 | 完整 | shrine_en.png |
| 帮助 | 完整 | help_en.png |
| 死亡结算 | 完整 | death_en.png |
| 瞄准 | 完整 | aim_en.png |
| 背包 | 完整（空包态） | inventory_en.png |
| 角色 | 完整 | character_en.png |

## 已覆盖内容

- 职业/资源/定位/天赋名与描述
- 敌人名/短名/意图/先攻
- 楼层/敌人/回合/等级/资源/热键栏
- 常见战斗日志（楼层/陷阱/宝箱/灼烧/升级/击杀/命中/伤害/Boss 阶段/商店/祭坛/战吼/闪现/回溯/举盾/FROST）
- 物品名/品质/属性细节
- 罗盘/楼梯标签

## 已知缺口

- 未覆盖的日志格式会回退中文
- 部分 tooltip/旧存档文本可能中文
- 物品 description 字段未在 UI 展示，未翻译
- 商店购买日志只覆盖 4 条常见项
- 没有英文语音/字幕
- 没有语言选择 UI 之外的本地化设置（字体/换行）

## Steam 语言声明

- 现在不应在商店勾选 English 为完整支持
- 可以在 Demo 页写 English beta available via settings
- 正式版英文化完成前，默认语言仍是简体中文

## 验证

- zig build test 232
- zig build test-qa 143
- zig build test-qa3 220
