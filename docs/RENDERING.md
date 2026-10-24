# 渲染与像素化

## 当前管线

这不是 SDL_GPU / 自定义 shader 的 3D 管线，而是 **CPU 软件光栅 + 低分辨率 framebuffer + 最近邻放大**：

1. 软件光栅器在 640×360 的 u32 颜色缓冲上做三角形填充、z-buffer、平面着色。
2. 每个像素经过 64 色调色板量化 + 有序抖动；光照按顶点/平面近似。
3. 整张 640×360 缓冲用 SDL_UpdateTexture 上传到 streaming texture（ARGB8888）。
4. 纹理采样设为 SDL_SCALEMODE_NEAREST。
5. SDL_SetRenderLogicalPresentation(640, 360, SDL_LOGICAL_PRESENTATION_INTEGER_SCALE)。
6. 窗口默认 3×（1920×1080），实际是整数倍放大，不做线性插值。

因此它属于“方案一：低分辨率目标 + 像素艺术缩放”的变体，但低分辨率目标是 **CPU framebuffer**，不是 SDL_GPU render target；像素化在 framebuffer 阶段已经完成，缩放阶段只负责锐利放大。

## 为什么不用 SDL_GPU + fragment shader

- 量化/抖动/调色板需要逐像素 CPU 访问；放 shader 里要重写整套光照、z-buffer 和调色板规则。
- 软件光栅保证 headless 截图确定性：同一 seed/帧数得到同一像素，QA 可直接 diff。
- 项目规模小（单英雄 + 十余敌人），CPU 光栅在 640×360 足够快。
- 没有自定义 shader，就不存在 SDL_SCALEMODE_PIXELART 被线性过滤覆盖的问题。

## 分辨率实验

同一 seed（12345）、同一帧、同一瞄准状态：

| 内部分辨率 | 结果 |
| --- | --- |
| 640×360 | 默认；中文 HUD、日志、天赋卡完整 |
| 480×270 | 3D 仍可读，但底部日志/提示被裁切，天赋卡重叠；见 docs/screenshots/res_480.png |
| 320×180 | 当前 --res 校验直接 BadResolution，不进入渲染 |

结论：640×360 是为 12px 中文 HUD 和 3D 细节折中的下限；再低会牺牲可读性。

## 备选方案与判断

1. **原生窗口分辨率渲染 + 后处理像素化**：像素边缘会随窗口变化，HUD 也要高分辨率重排；否决。
2. **SDL_GPU 全屏三角形 + floor(UV × resolution) 量化**：可控，但要重写渲染器；当前软件管线没有收益。
3. **SDL_SCALEMODE_PIXELART**：在非整数缩放下比 NEAREST 更稳；当前 INTEGER_SCALE 下与 NEAREST 等价，暂不引入。
4. **动态内部分辨率**：可作为性能选项，但 UI 需要单独适配 480×270；优先级低于上架功能。

## 相关入口

- --res WxH：内部分辨率（默认 640×360）
- --scale N：窗口整数倍（默认 3）
- F11 / --fullscreen：全屏
- F2：VSync / 窗口倍率
