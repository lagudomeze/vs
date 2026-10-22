# 属性 / 装备 / 物品 / 内容加载（程序 B 交付，ToME4 回合制方向）

分支 feat/attributes-items。模块完全独立：未改 game.zig / hud.zig / renderer / systems / actions。
设计依据：docs/TOME_V1.md（回合制 v1）；数值底表沿用 docs/BALANCE_V1.md，按回合制改写。

## 回合制约定

- 冷却、资源、增益/减速/停滞全部按回合计数（cooldown_turns / duration_turns），模块里没有任何 dt、秒数或前摇字段。
- 不做时间冻结 / Threat / 前摇：原 tactical 的 cast_time、potency、反制强度、移速(实时) 已移除。
- 六属性 -> HP / 资源 / 攻击 / 护甲 / 暴击 / 回合速度：
    HP       = 40 + 体质*8 + flat
    RESOURCE = 60 + 意志*4 + flat          （狂战士精力 / 元素法师法力 / 时空法师悖论）
    ATK      = 职业基础 + 主属性*1.2 + 武器 flat
    ARMOR    = 体质*0.5 + flat
    CRIT     = 5% + 感知*0.4%（上限 50%）
    SPEED    = 100 + (敏捷-10)*2（50..200，100 为基准）
    RES/TURN = 8 + 意志*0.35 + flat（每回合资源回复）
    伤害     = 原始 * (0.85 * 50/(50+护甲) + 0.15)，暴击 x1.5
- 百分比修正只乘基础值：value = base*(1+pct) + flat。

## 文件

| 文件 | 内容 |
| --- | --- |
| src/game/attributes.zig | StatKind / StatRef / Stats / Modifier / recompute / caps / Progression(XP/等级) |
| src/game/items.zig | ItemDef / Slot / Quality / Inventory / EquipmentSlots / ModifierSet / CharacterPanel |
| src/game/content.zig | 内嵌 JSON 解析、校验、内置回退、掉落抽取、职业天赋表 |
| assets/data/{items,enemies,skills}.json | 8 物品 / 6 敌人 / 9 玩家天赋 + 1 Boss 技能 |
| assets/data/data.zig | @embedFile 原始 JSON（Zig 不允许 embed 包外文件，故单独成模块） |

build.zig 给 vx 模块加了匿名导入 data；src/root.zig 导出 attributes / items / content。

## API 摘要

attributes.zig
- StatKind = strength / agility / constitution / perception / magic / will
- StatRef = 六属性 + hp_max / resource_max / attack / armor / crit / speed / resource_per_turn
- Modifier { stat, flat, pct, source }；source = base/level/equipment/buff/debuff
- Stats { base: [6]f32 }，get / set / add；baseStats(class) / classFromIndex(u8)
- Class = warrior / mage / chronomancer；profile(class).resource = ResourceKind{stamina,mana,paradox}；resourceLabel(class)
- recompute(base: Stats, mods: []const Modifier, class: Class) Sheet
  - Sheet.stats = 六属性最终值
  - Sheet.derived = { hp_max, resource_max, attack, armor, crit, speed, resource_per_turn }
  - caps：主属性 0..99、暴击 <=50%、速度 50..200、HP >=1、护甲 >=0
- damageAfterArmor(raw, armor) / resolveDamage(raw, armor, crit)
- Progression { level, xp }：xpToNext() = 100 × 当前等级；addXp(amount) 返回升了几级；progress01() 给 HUD 进度条
- applyLevels(stats, class, levels)：每级 +1 属性点，自动加到职业主属性（升级回满资源由 game 侧做）
- contribution(mods, ref) 给面板做数值溯源

items.zig
- Slot = main_hand / body / trinket / head / hands / feet（v1_slots 前三个）
- Quality = common / rare / epic / boss（qualityLabel / qualityTint）
- ItemDef { id, name, slot: ?Slot, quality, classes, weight, mods, use: ?Use, description }
- Inventory { items[12], len, equipped }：pickup / remove / has / equip(defs, id) / unequip(slot)
- ModifierSet：applyItem(id, def) / removeItem(id)（保持顺序）/ rebuild(defs, equipped) / slice()
- sheetFor(defs, equipped, base, class) 一步算装备后的 Sheet
- CharacterPanel + panelFor(defs, inv, base, class, progression, hp, resource)：
  给 UI 一次性提供 六属性、HP/资源（当前+上限）、装备槽（含 ItemDef 指针）、背包 ItemId 列表、等级/XP/升级进度、速度、职业资源名。
  panel.bag 与 panel.slots[].def 借用调用方的 Inventory / ItemDef 表，使用时保持它们存活。

content.zig
- Content { arena, items, enemies, skills, report }，load(allocator) / deinit()
- itemIndex(id) / item(id) / enemy(id) / skill(id) / talentsFor(class, out)（按数据顺序返回 3 个热键天赋）
- rollDrop(class, chance_roll, pick_roll, enemy)（30% 掉率 + 职业权重）
- Report { items/enemies/skills: embedded|fallback, issues[12] }，write(writer)
- EnemyDef { id, name, model, kind, hp, damage, armor, speed(回合), attack_range(格), attack_cooldown_turns, scale, xp, drop_chance, min_layer, max_layer, elite, boss, skill }
- SkillDef { id, name, kind: player|enemy, class, effect: damage|damage_knockback|attack_buff|blink|damage_slow|stun|recall,
             cost, cooldown_turns, damage_mult, flat_damage, range_cells, aoe_cells, knockback_cells, teleport_cells,
             buff_pct, duration_turns, slow_pct, description }
- 校验：唯一 id、数值范围、装备/消耗品一致性、敌人 kind 唯一、层数范围、敌人技能必须引用 enemy 技能、效果与参数一致（冲锋要击退格数等）
- 失败策略：按文件回退内置默认（builtin_items / builtin_enemies / builtin_skills）并记录 issue，不会崩

## 集成点（game.zig 未改）

1. 启动：Game.setup 里 content.load(self.gpa)，把 Content 存进 Game 字段；report.write(writer) 打日志（0.17 用 std.Io.File.stderr() + File.writer(io, buf)）。
2. 单角色：开局选职业 -> attributes.baseStats(class) 存进角色；装备/等级变化后 attributes.recompute(...) 写回组件（HP/资源上限、攻击、护甲、暴击、速度）。
3. 回合：玩家一次行动后跑敌人回合；技能冷却用 SkillDef.cooldown_turns 递减，资源按 Derived.resource_per_turn 每回合回复；不要用 dt。
4. 热键：content.talentsFor(class, &buf) 得到 1/2/3 天赋；cost / cooldown_turns 直接显示在 hotbar。
5. 敌人：content.enemies 按 min_layer/max_layer 过滤生成；hp/damage/armor/speed/attack_range/attack_cooldown_turns 直接读；Boss 的 skill 是 AOE。
6. XP：击杀/清层调 Progression.addXp(xp)；返回的级数交给 applyLevels，并回满 HP/资源。
7. 掉落：敌人死亡/宝箱 -> content.rollDrop(class, rand, rand, def)，成功则 inventory.pickup；背包满记日志。
8. 面板：C 键调 items.panelFor(...)，把 CharacterPanel 直接交给 hud.zig 画六属性/装备/背包/等级。
9. 伤害：普攻/天赋用 attributes.resolveDamage(attack * mult, target_armor, crit) 结算。

## 与最初任务的差异

- 按 ToME_V1 改为回合制：skills.json 由 3 技能扩为 9 个玩家天赋（每职业 3 个）+ 1 个 Boss AOE；移除 cast_time/potency/反制强度/实时移速。
- enemies.json 收录 6 种敌人（3 基础 + 2 精英 + 1 Boss，与 ToME_V1 第 7 节一致），并带 min_layer/max_layer 供关卡生成筛选。
- 敌人 kind：0 骷髅 / 1 幽魂 / 2 石魔像 / 3 深渊守卫 / 4 精英骷髅 / 5 精英幽魂。
- Zig 0.17 不允许 @embedFile 引用包外文件，所以 JSON 由 assets/data/data.zig 内嵌、build.zig 注册为 data 模块。
