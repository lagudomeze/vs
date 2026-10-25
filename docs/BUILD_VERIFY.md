# 发版包复验

日期：2026-10-25
HEAD：2893626

## 全量包

    tools/package.ps1

- dist/vx-0.1.0-win64.zip
- 2.6 MB
- vx.exe 7,887,360 bytes
- VERSION.txt = vx 0.1.0 / Windows x64
- SHA256 = 4FCECA0E860668D6D9D8E3C6C5C3987610DBA759AD1AFF7E2C719CA067638F63

steam_check：

    package: vx-0.1.0-win64.zip (2.6 MB)
    exe:     vx 0.1.0
    auto-cloud roots: .../lagudomeze/vx/saves
    OK: package is SteamPipe-ready (appid/depot still to fill)
    exit 0

steam_package_check：

    package version: vx 0.1.0
    WARN app_build still has YOUR_APP_ID
    WARN depot_build still has YOUR_DEPOT_ID
    steam package preflight: PASS
    exit 0

## Demo 包

    tools/demo_pack.ps1

- dist/demo/vx-demo-0.1.0.zip
- 2.6 MB
- SHA256 = 1778EE2DE0BB78EDA24D84FDB2CA9A0A5AD76828A168341FC609AEF65DB5C114
- 内容：vx.exe / PLAY_DEMO.cmd / DEMO_README.txt / README / CREDITS / OFL / VERSION

解包冒烟：

    vx: saves -> %APPDATA%/lagudomeze/vx/demo
    run headless: 640x360 ... floor=1 ... hp=184
    exit 0

HP 184 与战士平衡后的基础生命一致。

## 测试

    zig build test      262/262
    zig build test-qa   145/145
    zig build test-qa3  246/246

## 仍未验证

- 没有真实 AppID/DepotID
- 没有 Steamworks SDK/overlay/云冲突 UI
- 没有 Deck/Proton 实机
- 没有代码签名
- 没有真实 playtest 反馈
- 包内暂无正式 key art/实机 trailer

## 一键发版门禁

~~~powershell
pwsh -File tools/release_gate.ps1
pwsh -File tools/release_gate.ps1 -DryRun
~~~

顺序：preflight -> playtest_pack -> press_kit -> steam_check -> steam_package_check -> 三个 SHA。

## 一键 preflight

    $env:VX_PYTHON = <python.exe>
    tools/preflight.ps1

结果：PREFLIGHT PASS -SkipPackage（fmt、262/262、145/145、246/246、Deck 静态、i18n、截图）；package/steam_check/steam_package_check/demo_pack 单独通过。

## 商店 capture

- docs/store/gameplay_capture_30s.mp4（29.5s / 1920x1080 / 30fps / 约12MB，auto bot 引擎内录屏）
- docs/store/trailer_capture_30s.mp4（30s / 1080p30 / 约10.2MB，标题+字幕+结束卡）
- press kit zip 约25.3MB
