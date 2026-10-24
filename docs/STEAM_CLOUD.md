# Steam Auto-Cloud 配置

## 结论

先用 **Steam Auto-Cloud**，不接 Steamworks SDK。它不需要改代码，只要在 Steamworks 后台配置路径；游戏已经写入用户目录，天然适配。

等需要冲突 UI、跨平台选择、成就/Overlay 时再接 Cloud API / SDK。

## 当前路径

默认启动调用 SDL_GetPrefPath("lagudomeze","vx")，Windows 实际路径：

~~~text
%APPDATA%\lagudomeze\vx\saves\
~~~

验证：

~~~powershell
vx.exe --save-info
~~~

## 后台 Root Path 配置

| Root | Subdirectory | Pattern | Recursive |
| --- | --- | --- | --- |
| WinAppDataRoaming | lagudomeze/vx/saves | *.save | yes |
| WinAppDataRoaming | lagudomeze/vx/saves | records.json | no |

说明：

- 新存档是 slot1/2/3.save、autosave1/2/3.save，*.save 覆盖。
- records.json 单独同步，避免和 settings 混在一起。
- **不同步 settings.json**：全屏/VSync/窗口倍率是机器相关配置，不应跨机器覆盖。
- 旧版 run.json/gear.json 不在 Auto-Cloud 中；新格式已迁移，旧档只做本地兼容。
- OS Restriction 保持默认 Cross-Platform；未来若加 Linux，再配 Root Overrides。

## 配额

- Byte quota per user：建议 5 MB（当前存档 < 100 KB）。
- Number of files：64。
- 只同步 saves 下的小文件，不把日志/截图放进云路径。

## 测试

1. Steamworks 后台配置并 Publish。
2. 用拥有该 App 的账号启动 Steam。
3. Steam 控制台（steam://open/console）执行：

~~~text
testappcloudpaths <AppId>
set_spew_level 4 4
~~~

4. 启动游戏、存档、退出；看控制台上传。
5. 另一台机器启动，看下载。
6. 测试结束：

~~~text
testappcloudpaths 0
set_spew_level 0 0
~~~

日志：Steam 安装目录 logs/cloud_log.txt。

## 与 Cloud API 的取舍

Auto-Cloud：

- 优点：零代码、按文件同步、适合当前单机存档。
- 缺点：没有冲突选择 UI、不能按槽位精细控制、不能做动态同步。

Cloud API：

- 适合后续成就、Overlay、冲突提示、跨平台槽位管理。
- 需要 Steamworks SDK、appid、SteamAPI_Init、ISteamRemoteStorage。
- 当前机器没有 SDK，先不假装接入。

## 官方文档

- https://partner.steamgames.com/doc/features/cloud
- https://partner.steamgames.com/doc/sdk/uploading
