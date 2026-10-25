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
- F2 按 L 切换 ZH/EN，settings.language 持久化
- --lang en 可直接看英文设置/菜单

## 没有

- 暂停/BADGES 仍是英文固定文案（中文模式下不切换）
- HUD/战斗/日志/物品/敌人/职业卡未翻译
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

当前状态：**foundation only**，不是英文版。
