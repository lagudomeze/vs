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
- 帮助页 16 行
- 死亡/胜利标题、BEST/R RESTART
- 常见战斗日志（楼层/敌人/陷阱/宝箱/灼烧/升级/击杀/命中/伤害/Boss 阶段）
- 死亡原因
- 商店 6 项/祭坛 4 项/footer
- 罗盘 N/E/S/W、世界 STAIRS/STAIRS SEALED
- 物品名/品质/属性细节（IRON SWORD/RARE/ATK）
- 背包/角色面板标签、装备槽、天赋速查
- 瞄准提示 AIM/DIST/DMG/AOE、原因/天赋名
- 槽位菜单标题/空档/坏档/槽位摘要
- F2 按 L 切换 ZH/EN，settings.language 持久化
- --lang en 可直接看英文设置/菜单

## 仍缺

- 暂停/BADGES 仍是英文固定文案（中文模式下不切换）
- 未知日志格式回退中文
- 少量 tooltip/旧存档文本
- 444 去重字符串审计中仍有未映射项（含中文 fallback 噪声）
- 没有英文语音/字体排版专项验收

## 下一批

1. 未知日志格式/商店购买日志兜底
2. tooltip/旧档文本
3. 英文长文本换行/溢出逐屏验收

## 约束

- 不发布“半英半中”作为正式英文支持
- 英文字符串更长，必须逐屏截图
- 历史日志在切换语言后会重新翻译显示
- CJK 字体子集不影响 ASCII，但英文排版需重新测宽

当前状态：**导航 + 职业卡 + 核心 HUD 部分英文**，不是完整英文版。截图：settings_en.png / menu_en.png / gameplay_en.png / help_en.png / death_en.png / shop_en.png / shrine_en.png / inventory_en.png / character_en.png / aim_en.png；日志为显示层翻译，存档仍存中文。
