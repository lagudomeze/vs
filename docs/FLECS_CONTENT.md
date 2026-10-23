# FlecsScript 作为内容组合层：可行性判断

> 结论：**值得做，但只建议先做 content/definition world，不建议把 Sim 整体迁过去。**
> ItemDef / SkillDef 可以最终删除，但前提是补上反射、稳定 DefId、DefCatalog 和存档边界。
> 现在直接删会得到“运行时脚本 + 无法赋值 + 两套内容源”的更差结果。

## 1. FlecsScript 能解决什么

FlecsScript 是运行时实体 DSL，定位是 scene/asset/config：

- 命名实体、层级、继承；
- 给组件赋值；
- 变量、条件、循环；
- prefab / 模板 / 组合。

这正好适合：

- Item 作为 prefab：Item + EquipSlot + 多个 Modifier + Consumable；
- Skill 作为 prefab：Skill + Cost + Cooldown + DamageEffect/StatusEffect；
- Enemy 作为 prefab：Enemy + Combat + AI + Loot + Spawn；
- Class 作为 prefab：Class + PrimaryStats + HasSkill 关系。

它不是：

- 公式系统；
- 编译期类型检查器；
- 存档格式；
- 自动替代运行时校验。

## 2. 当前 zflecs 的关键限制

zflecs 0.2.0-dev 已经包含：

- FLECS_SCRIPT addon（build option script_addon=true）；
- ecs.script_run / script_parse / script_eval；
- ecs.struct_init / struct_desc_t；
- ecs.COMPONENT。

但 Zig 侧当前注册组件只做了：

~~~zig
ecs.COMPONENT(world, T)
~~~

它注册 size/alignment/name，**没有注册反射字段**。FlecsScript 文档明确说：

> 组件要能用 value 赋值，必须由 reflection framework 描述。

所以现状是：

- 脚本可以 Item / Skill 这样加 tag；
- 但 Cost: {value: 25} 这类字段赋值会失败，除非补 ecs_struct_init 的字段描述。
- 这不是语法问题，是 Zig 组件反射层没做。

## 3. 如果要走，先补反射

需要一个 content/reflect.zig：

- 用 @typeInfo 遍历 Zig 组件字段；
- 生成 ecs_struct_desc_t（name/offset/type）；
- 标量 f32/u16/u8/enum 可反射；
- 字符串不要直接放 []const u8，改为 TextKey / Identifier / 原子 ID；
- 每个 content 组件注册一次。

另外：

- 多个 Modifier 不能塞进同一个组件（ECS 一个实体一个组件）；
- 用子实体：
  - sword_prefab 下挂 modifier_attack / modifier_strength；
- 或用 pair 关系 (Modifier, Stat)。

这也是“细分组件”的关键：不要把 modifiers: []Modifier 又做成一个胖组件。

## 4. 建议的组件拆分

### Item prefab

~~~text
Item
DefId (u32, 稳定)
DisplayName (TextKey)
Description (TextKey)
Quality (enum)
EquipSlot (enum, optional component)
Modifier (child entity, one per stat)
Consumable (heal/resource)
DropRule (classes bitmask, weight)
Icon (optional)
~~~

### Skill prefab

~~~text
Skill
DefId
DisplayName
Description
Cost
Cooldown
Range
TargetShape
DamageEffect
SlowEffect
StunEffect
BlinkEffect
RecallEffect
ClassTag
~~~

一个技能只挂它需要的 effect 组件。闪现没有 DamageEffect；火球有 DamageEffect + AoE。

### Enemy prefab

~~~text
Enemy
DefId
DisplayName
Model
CombatProfile
AIProfile
LootProfile
SpawnProfile
EliteTag / BossTag
HasSkill
~~~

### Class prefab

~~~text
Class
DefId
DisplayName
PrimaryStats
ResourceKind
BaseAttack
HasSkill (relationship)
~~~

## 5. 删除 ItemDef/SkillDef 后还需要什么

“不用 ItemDef”不等于“不需要读取模型”。

建议：

- 脚本 prefab 是唯一 authoring 源；
- 启动时从 world 查询并构建 **只读 DefCatalog**；
- DefCatalog 是 view，不是 authoring 结构：
  - ItemView { def_id, name_key, slot, modifier_children... }
  - SkillView { def_id, cost, cooldown, effect components... }
- Sim/HUD 只拿 DefId 和 view；
- 存档只存 DefId，不存 entity_t。

如果没有 DefCatalog：

- 每个系统都要做 ECS query；
- 预览/UI 需要重复查询；
- 存档需要 entity id，跨会话不稳定。

## 6. 确定性 / 存档 / 测试

必须解决：

- **稳定 ID**：每个 prefab 有 DefId/GUID；不能依赖 entity 创建顺序。
- **查询顺序**：所有内容列表按 DefId 排序；不假设 ECS 迭代顺序。
- **存档**：存 DefId，不存 entity_t；加载时按 DefId 解析，缺失就报错/回退。
- **QA**：内容 world 必须在 headless/unit test 中可初始化；不能依赖 SDL。
- **错误处理**：script_run 返回错误 + error_ 字符串；坏内容回退或拒绝启动。
- **热重载**：dev 可以 script_update，但运行时引用的 DefId 必须仍存在。

## 7. 与 Sim 的边界

推荐：

- ContentWorld（zflecs + FlecsScript）：只读定义；
- Sim（纯数组）：回合、属性、伤害、AI；
- Render（zflecs）：Transform/Renderable/Light 投影；
- DefCatalog：ContentWorld -> Sim/HUD 的只读快照。

不推荐现在把 Sim 整体迁 zflecs：

- 存档、确定性、QA 全部要重写；
- 单英雄 + 12 敌人不需要 ECS 查询；
- 只会把复杂度从“数据建模”转移到“调度/序列化”。

## 8. 迁移阶段

### Phase 0：探针

- 注册一个 Item 组件；
- ecs_struct_init 描述 value；
- 运行最小 .flecs：
  ~~~text
  Item {}
  iron_sword {
    Item
    Cost: { value: 25 }
  }
  ~~~
- 查询并读回值；
- 验证脚本错误报告。

如果 Phase 0 的反射不通过，不要进入 Phase 1。

### Phase 1：ContentWorld

- FlecsScriptImport；
- 组件注册 + 反射；
- 加载 items.flecs / skills.flecs / enemies.flecs；
- 构建 DefCatalog；
- 与现有 JSON 内容做对比测试（同一组 ID/数值）。

### Phase 2：替换定义

- ItemDef/SkillDef/EnemyDef 从代码删除；
- 只保留 DefCatalog view；
- content loader 从 scripts 读取；
- JSON 只用于存档/本地化/迁移。

### Phase 3：可选实例 ECS

- 如果要做词缀/耐久/附魔，再引入 ItemInstance entity；
- 否则 Inventory 继续存 DefId 即可。

## 9. 风险清单

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| 反射未注册 | 脚本只能加 tag，不能赋值 | Phase 0 先做 reflect |
| 字符串反射 | []const u8 不能直接赋值 | TextKey/Identifier |
| entity id 不稳定 | 存档/热重载失效 | DefId/GUID |
| 查询顺序不稳定 | QA 漂移 | 按 DefId 排序 |
| 多 Modifier | 一个组件只能挂一份 | 子实体/pair |
| 运行时错误 | 启动崩溃 | script error 报告 + fallback |
| 测试需 zflecs world | 单测变重 | 小 fixture world |
| 两套内容源 | 数据漂移 | 一次只保留 scripts |

## 10. 判断

- **ItemDef / SkillDef 可以删**，但它们是“authoring 结构”；删掉后需要 DefCatalog view 和反射层。
- **FlecsScript 适合做内容组合**，不适合做数值系统。
- **先 content-only**，不要全 Sim 迁移。
- **先 Phase 0 探针**；如果反射层成本过高，就继续用 Zig comptime 表，而不是退回胖 JSON。

在当前代码上，直接删 ItemDef/SkillDef 会破坏：
- items/skills loader；
- 装备/天赋 UI；
- 存档物品 ID 校验；
- QA 内容数量断言。

所以顺序必须是：反射 -> ContentWorld -> DefCatalog -> 替换，而不是先删结构。
