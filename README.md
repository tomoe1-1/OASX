# OASX

[OnmyojiAutoScript](https://github.com/tomoe1-1/OnmyojiAutoScript) 的**桌面控制端**，
基于 Flutter Windows 构建。

本仓库同时包含**可运行产物**与**完整构建源码**：

| 位置 | 内容 | 用途 |
|---|---|---|
| 仓库根目录 | 发布产物（release build）+ `OASInputRecorder/` | clone 后双击 `oasx.exe` 直接运行 |
| [`src/`](src/) | 完整 Flutter 源码（414 文件） | 自行 `flutter build windows --release` 重新构建 |

- 当前版本：**v1.0.0**（首个自构建正式版）
- 产物来源：由 `src/` 构建，构建工具链 Flutter 3.47.5 / Dart 3.13.4
- 应用内「检查更新」指向本仓库 releases，**不会**被上游发版覆盖

> v0.3.14 及更早：同步自上游 [`xylolit-mu/OASX`](https://github.com/xylolit-mu/OASX)
> 的 Windows 发布包，逐文件 SHA256 校验后镜像，未做改动。

## 目录结构

```
OASX/
├─ oasx.exe                              # 主程序入口（双击运行）
├─ flutter_windows.dll                   # Flutter Windows 运行时
├─ ui-check.txt                          # 自检结果
├─ *_plugin.dll                          # 各功能插件（见下）
├─ data/
│  ├─ app.so                             # Dart AOT 编译产物（核心逻辑）
│  ├─ icudtl.dat                         # ICU 国际化数据
│  └─ flutter_assets/                    # 界面资源
│     ├─ assets/images/                  #   应用图标
│     ├─ assets/records/                 #   内置示例操作记录（CSV）
│     ├─ fonts/                          #   Material 图标字体
│     ├─ packages/                       #   Cupertino / FontAwesome 图标字体
│     └─ shaders/                        #   渲染着色器
├─ src/                                  # ★ 完整 Flutter 源码（可重新构建）
│  ├─ lib/                               #   Dart 源码（252 个文件）
│  ├─ windows/                           #   Windows 平台原生壳（C++）
│  ├─ pubspec.yaml                       #   依赖清单与版本号
│  ├─ assets/                            #   随源码打包的静态资源
│  └─ .gitignore                         #   构建产物忽略规则
└─ OASInputRecorder/                     # 配套的只读操作记录器（独立工具）
```

### 插件 DLL 说明

| 文件 | 用途 |
|---|---|
| `window_manager_plugin.dll` | 无边框窗口、窗口尺寸与位置控制 |
| `system_tray_plugin.dll` | 系统托盘图标与菜单 |
| `screen_retriever_windows_plugin.dll` | 屏幕信息读取（分辨率、多屏） |
| `url_launcher_windows_plugin.dll` | 调起外部浏览器 / 链接 |
| `connectivity_plus_plugin.dll` | 网络连通性检测 |
| `super_native_extensions.dll` | 原生扩展运行时（拖放等） |
| `super_native_extensions_plugin.dll` | 原生扩展插件入口 |
| `irondash_engine_context_plugin.dll` | Flutter 引擎上下文桥接 |

## 运行要求

- Windows 10 / 11（x64）
- 已安装对应版本的 [OnmyojiAutoScript](https://github.com/tomoe1-1/OnmyojiAutoScript) 并完成配置
- 无需安装 Flutter SDK —— 所有运行时依赖已随包附带

双击 `oasx.exe` 即可启动。

## 从源码构建

`src/` 是**完整可编译**的 Flutter 工程，无需上游仓库即可独立构建：

```bash
cd src
flutter pub get
flutter build windows --release
# 产物：src/build/windows/x64/runner/Release/oasx.exe
```

工具链版本（与仓库根目录运行产物一致）：

| 组件 | 版本 |
|---|---|
| Flutter | 3.47.5（stable） |
| Dart | 3.13.4 |

> **Windows 构建前置**：Flutter 在 Windows 上构建带插件的工程需要符号链接权限。
> 若报 `Building with plugins requires symlink support`，请开启「开发者模式」
> （设置 → 系统 → 开发者选项），或以管理员身份运行终端。

构建产物**不入库** —— `src/.gitignore` 已排除 `build/`、`.dart_tool/`
以及各平台的构建中间产物（`android/build/`、`windows/flutter/ephemeral/` 等）。
如需更新仓库根目录的运行产物，从
`src/build/windows/x64/runner/Release/` 手动同步 `oasx.exe`、`data/` 与各 `*_plugin.dll`。

> 源码历史由 git 子树合并保留（`git-subtree-dir: src`），包含上游
> [`xylolit-mu/OASX`](https://github.com/xylolit-mu/OASX) 的完整提交脉络。
> 后续同步可用 `git subtree pull --prefix=src <上游地址> self`。

## 状态自检

```
OASX UI package check
Version: v1.0.0
Storage: OK
Window plugin: oasx
Original CSV assets: 3
Tools page first frame: OK
Design tokens: spacing / radii / motion / type-scale / semantic-colors / surfaces
Reduce-motion respected: YES
PASS
```

## 关于 OASInputRecorder

`OASInputRecorder/` 是一个**只读**的辅助工具：解析 OnmyojiAutoScript 的日志文件，
把玩家真实操作（点击、滑动）提取出来，用于生成更贴近真人手感的操作脚本。

它**不注入、不挂钩、不修改**游戏进程，只读取 OAS 自己写出的文本日志。

详见 [`OASInputRecorder/README.md`](OASInputRecorder/README.md)。

## 仓库说明

- 本仓库同时托管**可运行产物**（根目录）与**构建源码**（`src/`）
- `logs/`（本地运行日志）与 `.workbuddy/`（本机工作目录）已在 `.gitignore` 中排除
- 源码的 `build/`、`.dart_tool/` 等构建产物由 `src/.gitignore` 排除，不会入库
- `data/flutter_assets/assets/records/` 下的 3 个 CSV 是**界面内置的示例资源**，属于程序正常运行所需，已一并入库
