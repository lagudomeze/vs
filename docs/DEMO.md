# Demo 构建与分发

状态：可生成 zip；尚未创建独立 Steam Demo App/Depot。

## 生成

~~~powershell
zig build -Doptimize=ReleaseFast
pwsh -File tools/package.ps1
pwsh -File tools/demo_pack.ps1
~~~

产物：dist/demo/vx-demo-<version>.zip（约 2.6 MB）。

## 内容

- vx.exe（完整程序，--demo 门禁；仅狂战士）
- PLAY_DEMO.cmd：start "" "%~dp0vx.exe" --demo
- DEMO_README.txt：只开第 1 层、独立存档、F2/F3/F4
- README/CREDITS/OFL

## 存档隔离

--demo 把进程根切到：

~~~text
%APPDATA%\lagudomeze\vx\demo\
  saves\slot1.save ...
  saves\settings.json
  saves\records.json
~~~

正式版仍在 %APPDATA%\lagudomeze\vx\saves，两者互不迁移、互不覆盖。

## Steam Demo 配置

- 需要单独 Demo App/Depot（Valve 后台申请）
- Launch option：vx.exe，Arguments --demo
- 不要把正式版 AppID 写进 Demo
- Demo 存档独立；正式版不读取 demo 目录
- Demo 内不显示完整版成就/记录

## 验收

- [ ] PLAY_DEMO.cmd 能启动
- [ ] 只到第 1 层，楼梯结束
- [ ] demo 目录独立
- [ ] F4 诊断/反馈可用
- [ ] 不覆盖正式存档
- [ ] 不含 steam_appid.txt

## 未完成

- ~~Demo 只开一个职业~~（已实现：仅狂战士，2/3 显示 DEMO LOCKED）

- 独立 Demo App/Depot
- Demo 商店页/预告片
- 从 Demo 导入愿望单/进度
