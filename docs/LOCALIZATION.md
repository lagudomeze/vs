# 本地化实现状态

## 已有

- src/game/i18n.zig：Lang(zh/en)、全局 current、t(zh,en)
- Settings.language（0=zh,1=en，持久化，sanitized 夹取）
- CLI：--lang zh | en
- --save-info 输出 lang
- 单测：语言切换、非法值回退、设置夹取

## 已接入（导航层）

- 设置面板标题、11 行、值行、footer
- 菜单标题、seed 行、footer
- 职业卡：职业名/资源/定位/三个天赋名与描述
- 核心 HUD：等级、楼层、敌人、回合、先攻、职业资源、热键栏状态
- 敌人名/短名、意图（ATK/RANGED/CHASE/STUN）、先攻 YOU
- F2 按 L 切换 ZH/EN，settings.language 持久化
- --lang en 可直接看英文设置/菜单

## 没有

- 暂停/BADGES 仍是英文固定文案（中文模式下不切换）
- 战斗日志/物品/商店/祭坛/帮助/结算/天赋瞄准提示未翻译
- 没有语言选择 UI（F2 里没有）
- 没有英文截图/字体溢出验收
- 没有内容翻译（406 去重字符串）

## 下一批

1. 设置/暂停/主菜单/帮助（导航）
2. HUD 标签/天赋/状态/意图（战斗）
3. 物品/敌人/楼层/日志（内容）

## 约束

- 不发布“半英半中”作为正式英文支持
- 英文字符串更长，必须逐屏截图
- 历史日志切语言后不会重译
- CJK 字体子集不影响 ASCII，但英文排版需重新测宽

当前状态：**导航 + 职业卡 + 核心 HUD 部分英文**，不是完整英文版。截图：settings_en.png / menu_en.png / gameplay_en.png。
