# 音频

## 现状

程序化音效 + 低频环境音 + 稀疏五声音阶 motif，无外部音频文件：

- step：短方波
- hit：低频方波 + 噪声
- cast：正弦
- pickup：高音
- death：下降音
- ui：短提示音

环境音：55/82.41/110Hz 三层正弦 + 慢 LFO；五声音阶 motif 按场景切换：

- explore：220–392Hz，0.55s/音
- danger：110–196Hz，0.40s/音，drone 更重
- shop：大调 261–523Hz，0.80s/音，更轻
- death：82–110Hz，1.10s/音
- victory：大调 261–659Hz，0.50s/音

约 2048 样本一块，队列低于 10000 字节时补充；与 SFX 共用一条 stream。

实现：src/platform/sdl.zig

- SDL_InitSubSystem(SDL_INIT_AUDIO)
- SDL_OpenAudioDeviceStream(F32, mono, 22050Hz)
- 事件发生时生成 PCM，SDL_PutAudioStreamData 入队
- 队列超过约 1 秒时丢弃新音效，避免积压

## 音量

- F2 设置面板：4 VOLUME 循环 0 / 55 / 100%
- settings.json 持久化 volume/ambient
- 启动时 SDL_SetAudioStreamGain / setAmbient
- F2 第 5 项开关环境音

## 氛围切换

主窗口 RunGame 循环每帧根据状态选择 mood：死亡/胜利/商店/Boss 或低血量危险/普通探索；旧演示 Game 循环不再承担正式音频。

## 触发

主循环比较 update 前后的 sim 状态：

- 英雄掉血 -> hit
- 击杀 -> pickup
- 玩家回合推进 -> step
- 输入带天赋且回合推进 -> cast
- 死亡 -> death
- F2/F11 -> ui

这是事件近似，不是逐动作 ActionSpec 音效；后续可在 Sim 里加 SoundEvent 队列做精确触发。

## 未做

- 完整多轨编曲/分层 BGM（当前为 drone + 单声部 motif）
- 空间音频/声像
- 音频设备选择
- 音量淡入淡出/限幅
- 自动化音频测试（依赖设备）

这些不影响当前上架最小版本；多轨 BGM 仍是下一步体验重点。
