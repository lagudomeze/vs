# Steam 启动项 / Deck / 首启配置

状态：配置清单，不是 Steamworks 已发布。真实 AppID/DepotID 仍需后台创建。

## 1. 启动项

Steamworks 后台 → Installation → General：

| 字段 | 值 |
| --- | --- |
| Executable | vx.exe |
| Arguments | 留空 |
| Working Directory | 留空（包根） |
| OS | Windows |
| Type | Default |

不要：

- 加 --portable（会写安装目录，可能只读）
- 加 --headless / --auto / --seed（开发用）
- 指向 dist 子目录里的 exe（包根必须直接有 vx.exe）

## 2. Depot 根

- ContentRoot：dist/vx-<version>-win64
- vx.exe 在根目录
- 不包含 steam_appid.txt、.pdb、saves、日志、截图
- 模板见 steam/depot_build.vdf.example

预检：

~~~powershell
pwsh -File tools/package.ps1
pwsh -File tools/steam_package_check.ps1
pwsh -File tools/steam_check.ps1
~~~

## 3. Auto-Cloud

见 [STEAM_CLOUD.md](STEAM_CLOUD.md)。

关键：

- 同步 saves/*.save + records.json
- 不同步 settings.json
- 配额 5 MB / 64 files
- 不同步 .bak / 日志
- Auto-Cloud 没有冲突选择 UI；覆盖前先做本地备份/测试

## 4. Steam Deck

目标：Playable，不承诺 Verified。

| 项目 | 检查 |
| --- | --- |
| 分辨率 | 1280×800，3× 整数缩放，无拉伸 |
| 文字 | HUD/天赋/商店在掌机距离可读 |
| 控制 | 左摇杆/D-pad 移动，A 确认，B 取消，肩键天赋，右摇杆镜头 |
| 地图 | 右摇杆按下打开，M 不需要 |
| 设置 | F2 不可用；默认窗口/音量可玩，不改也能玩 |
| 暂停/恢复 | Esc 打开 PAUSED；Esc 恢复、Q/Start 两次退出、暂停静音；切出再回来不崩、不丢回合 |
| 性能 | 60fps 目标；掉帧时先看窗口倍率/全屏 |
| 存档 | 退出后重进，槽位/自动档可读 |
| 云 | Auto-Cloud 上传/下载不覆盖 settings |

已知缺口：

- 未接 Steam Input 官方配置（SDL gamepad）
- 无原生 Linux 构建；Proton 未验证
- 手柄键位不可重绑
- 无暂停菜单（Esc 直接退）

## 5. 首启检查

在干净 Windows 用户下：

1. 解压/安装，启动，不出现控制台。
2. 开始菜单能看到三职业。
3. F2 打开/关闭设置，F4 复制诊断。
4. 存一个槽位，退出，再进，F9 能读。
5. 检查 %APPDATA%\lagudomeze\vx\saves。
6. 卸载/删除后不残留安装目录写入。

## 6. 发布前清单

- [ ] AppID/DepotID 已创建
- [ ] 启动项 vx.exe / 无参数
- [ ] depot 根有 vx.exe
- [ ] steam_appid.txt 不在包内
- [ ] Auto-Cloud 路径已 Publish
- [ ] 两台机器云同步测试
- [ ] Deck 手柄/分辨率/恢复测试
- [ ] 商店页素材/隐私说明
- [ ] 回滚构建保留
