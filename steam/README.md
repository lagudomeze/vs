# Steam 上传

这些是模板，不要直接提交真实 AppID/DepotID 的构建脚本。

## 1. 生成包

~~~powershell
pwsh -File tools/package.ps1
~~~

产物：dist/vx-0.1.0-win64/ 与 dist/vx-0.1.0-win64.zip。

## 2. 填模板

~~~powershell
Copy-Item steam/app_build.vdf.example steam/app_build.vdf
Copy-Item steam/depot_build.vdf.example steam/depot_build.vdf
~~~

替换：

- YOUR_APP_ID
- YOUR_DEPOT_ID

保持路径使用正斜杠，避免 VDF 转义问题。

## 3. 上传

~~~powershell
steamcmd +login <account> +run_app_build "C:/path/to/vx/steam/app_build.vdf" +quit
~~~

首次上传前在 Steamworks 后台创建 App/Depot，并配置启动项为 vx.exe。

## 4. 检查

~~~powershell
pwsh -File tools/steam_check.ps1
~~~

检查包、版本、steam_appid.txt 泄漏、Auto-Cloud 路径。

## 5. Steam Input

模板见 [steam_input_manifest.vdf.example](steam_input_manifest.vdf.example) 与 [docs/STEAM_INPUT.md](../docs/STEAM_INPUT.md)。预检：pwsh -File tools/steam_input_check.ps1。当前未接 SDK，构建仍用 SDL gamepad。

## 6. Auto-Cloud

见 [docs/STEAM_CLOUD.md](../docs/STEAM_CLOUD.md)。不需要 Steamworks SDK。

## 7. 不要提交

- steam/app_build.vdf
- steam/depot_build.vdf
- steam_appid.txt
- dist/
