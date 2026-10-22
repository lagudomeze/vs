# 资源管线

## 依赖

- Python 3.10+
- Pillow（`pip install pillow`）

运行时**不需要** Python；`assets/baked/*.vxm` 与 `assets/assets.zig` 已提交并内嵌到可执行文件。

## 一键重建

```powershell
python tools/characters.py
python tools/bake_assets.py
zig build
```

## 角色

`tools/characters.py`：

- 定义材料表、共享身体、三套职业部件、关节层级。
- 几何原语在 `geometry.py`：锥台、锥、盒、低模球、圆环、任意方向圆柱、八面体。
- 三角面自动朝外（按局部中心/法线提示翻转），每个三角形归属一个关节组。
- 导出：
  - `assets/models/<name>.obj`：标准 OBJ，`o <joint>` 分组，`usemtl` 使用 MTL 颜色；
  - `assets/models/<name>.mtl`：sRGB Kd / 自发光 Ke；
  - `assets/models/<name>.rig.json`：关节父子关系、rest offset、pivot 世界坐标，供烘焙器把顶点变换到关节局部空间。

## 烘焙

`tools/bake_assets.py`：

1. **角色**：解析 OBJ/MTL，按 `o` 组确定关节；顶点减去该关节世界 pivot；MTL 颜色逐面写入。
2. **Kenney**：解析 OBJ/MTL/colormap.png；按每个面的 UV（以及重心）采样纹理颜色（取众数，忽略纯黑边），并归一化到地面中心；合并重复面。
3. **程序化道具**：火盆、晶塔、占位碎片（mote）、符文圈；颜色 + 自发光标记。
4. **写出 VXM**（格式见 `docs/ARCHITECTURE.md§3`）。
5. **生成清单** `assets/assets.zig`：所有文件名 + 内嵌字节数组。
6. **生成版权信息** `assets/CREDITS.md`（从 Kenney License.txt 读取）。

## 增加一个 Kenney 道具

1. 把 OBJ/MTL 放到 `assets/kenney/<pack>/Models/OBJ format/`（colormap 放在 `Textures/colormap.png`）。
2. 在 `KENNEY_PROPS` 里加一行：`("my_prop", "<pack>", "my-prop.obj")`。
3. 重新烘焙。
4. 在 `game.zig` 的 `spawnArena` 里 `spawnPropEntity("my_prop", pos, yaw, scale, shadow_radius)`。

## 修改角色

- 直接改 `tools/characters.py` 的几何/材质/关节，重新生成 + 烘焙。
- 或在 Blender 里编辑 `assets/models/<name>.obj`（保持 `o` 关节名），导出 OBJ 后重新烘焙。
- 若新增关节，在 `src/engine/rig.zig` 里加对应动画（按 `Model.xxx` 命名槽访问），否则该关节保持 rest 姿态。

## VXM 注意点

- 顶点/索引是小端；颜色为 sRGB + `emissive` 字节。
- 每个部件的三角形颜色是逐三角形的，渲染器计算面法线做平面着色；若需要平滑法线，需要扩展格式与光栅器。
- 模型坐标单位为“米”，角色约 1.0–1.2 高；游戏里通过 `Transform.scale`（英雄 1.4）缩放。
- 资源内嵌在 `assets/` 目录下，`@embedFile` 的相对路径以 `assets/assets.zig` 为基准。
