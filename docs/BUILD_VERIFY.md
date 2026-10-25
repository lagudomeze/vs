# 发版包复验

日期：2026-10-25
HEAD：d25ecf2


> Zip 由 tools/zip_dir.ps1 生成：条目排序 + 固定 1980 时间戳。同样内容重建 SHA 一致（全量/Demo/Playtest/Press 已连续两次全链验证）。

## 全量包

    tools/package.ps1

- dist/vx-0.1.0-win64.zip
- 2.6 MB
- vx.exe 7,900,160 bytes
- VERSION.txt = vx 0.1.0 / Windows x64
- SHA256 = 9306ADF5B1FEBA4DA58CF762BF70BCF67AAE1457B0A04C194A7DEBB73A72B9B4

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
- SHA256 = 4329215E53F0FF9B40C9500DB01658D961FCFBC4E77D432DEADA6CB8C8ECE4FD
- 内容：vx.exe / PLAY_DEMO.cmd / DEMO_README.txt / README / CREDITS / OFL / VERSION

解包冒烟：

    vx: saves -> %APPDATA%/lagudomeze/vx/demo
    run headless: 640x360 ... floor=1 ... hp=184
    exit 0

HP 184 与战士平衡后的基础生命一致。

## 测试

    zig build test      271/271
    zig build test-qa   145/145
    zig build test-qa3  255/255

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

## 可复现性验证

~~~powershell
pwsh -File tools/verify_repro.ps1 -SkipPreflight
~~~

连续两次 gate，比较全量/Demo/Playtest/Press SHA；任何 DIFF 直接失败。

## 文档链接检查

preflight 会跑 tools/check_links.py；断链直接失败。两个 i18n 审计以 --check 运行：文档过期会失败，且不再改写工作区。

## 一键 preflight

    $env:VX_PYTHON = <python.exe>
    tools/preflight.ps1

结果：PREFLIGHT PASS -SkipPackage（fmt、271/271、145/145、255/255、Deck 静态、i18n、截图）；package/steam_check/steam_package_check/demo_pack 单独通过。

## 商店 capture

- docs/store/gameplay_capture_30s.mp4（29.5s / 1920x1080 / 30fps / 约12MB，auto bot 引擎内录屏）
- docs/store/trailer_capture_30s.mp4（30s / 1080p30 / 约10.2MB，标题+字幕+结束卡）
- press kit zip 约25.3MB
