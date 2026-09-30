# OASX 2.x

[OnmyojiAutoScript](https://github.com/tomoe1-1/OnmyojiAutoScript) 的**桌面控制端**，
基于 Flutter Windows 构建。

**当前版本：v2.0.0** —— 包含主页动态背景、启动页重绘，以及窗口位置和 OAS 目录恢复修复。

本次启动修复详见 [启动修复说明](./启动修复说明.md)。窗口位置配置异常或显示器断开时恢复为居中窗口；保存的 OAS 目录失效时识别相邻有效安装，无法识别则提供目录选择和重新连接入口。

## 两条获取途径

| 方式 | 适合谁 | 怎么做 |
|---|---|---|
| **下载发行包**（推荐普通用户） | 只想直接用 | 到 [Releases](../../releases/latest) 下载 `oasx_v2.0.0_windows.zip`，解压即用 |
| **clone 本仓库** | 想改代码 / 看实现 | `git clone`，根目录已是可运行的发行目录，同时含 `src/` 完整源码 |

> 本仓库的**根目录同时就是发行目录** —— clone 下来双击 `oasx.exe` 即可运行，
> 无需再从别处复制文件。

## 目录结构

```
OASX/                            # 仓库根目录 = 发行目录
├─ oasx.exe                      # 主程序入口（双击运行）
├─ flutter_windows.dll           # Flutter Windows 运行时
├─ *_plugin.dll                  # 各功能插件（见下表）
├─ build-info.json               # 版本号与产物 SHA256 校验
├─ data/
│  ├─ app.so                     # Dart AOT 编译产物（核心逻辑）
│  ├─ icudtl.dat                 # ICU 国际化数据
│  └─ flutter_assets/            # 界面资源
│     ├─ assets/images/          #   应用图标
│     ├─ assets/splash/          #   启动页与主页背景资源
│     ├─ fonts/                  #   Material 图标字体
│     └─ shaders/                #   渲染着色器
├─ src/                          # ★ 完整 Flutter 工程（可重新构建）
├─ tools/                        # 资源清单同步 / 手工构建 / 版本资源工具
├─ docs/                         # 项目文档（含视觉验收页）
└─ LICENSE
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
- 无需安装 Flutter SDK —— 所有运行时依赖已随包附带
- 首次启动会自动定位 OAS 目录（见下）

双击 `oasx.exe` 即可启动。**请保持 `data` 目录与所有 DLL 和 exe 位于同一目录。**

## 默认 OAS 私库

首次启动且未保存 OAS 位置时，默认使用 `..\OAS\OnmyojiAutoScript-easy-install`。

- 默认仓库：`git@github-oas:tomoe1-1/OAS-tomoe.git`
- 默认分支：`self`

> 已保存且有效的 OAS 位置、或 `deploy.yaml` 中明确配置的仓库与分支，**优先于**上述默认值。保存的目录失效时，仅检查程序旁经过验证的 OAS 安装，不对错误目录自动执行部署。

## 从源码构建

`src/` 是完整可编译的 Flutter 工程：

```powershell
cd src
flutter pub get
flutter build windows --release --build-name 2.0.0 --build-number 20
```

产物位于 `src\build\windows\x64\runner\Release`，把该目录下全部运行文件复制到发行目录即可。

`tools/build_manual.sh` 用于已有原生 runner 的手工 AOT 构建，需要显式设置
`FLUTTER_ROOT`、`PYTHON_BIN`，以及同插件版本生成的 `dart_plugin_registrant.dart`。

| 组件 | 版本 |
|---|---|
| Flutter | 3.47.5（stable） |
| Dart | 3.13.4 |

> **Windows 构建前置**：Flutter 在 Windows 上构建带插件的工程需要符号链接权限。
> 若报 `Building with plugins requires symlink support`，请开启「开发者模式」
> （设置 → 系统 → 开发者选项），或以管理员身份运行终端。

## 版本与校验

`build-info.json` 记录版本与产物哈希：

| 字段 | 值 |
|---|---|
| version / build | `2.0.0` / `20` |
| 工具链 | Flutter 3.47.5 / Dart 3.13.4 |
| 平台 | windows-x64 |

已核验与实物一致：

| 文件 | SHA256 |
|---|---|
| `data/app.so` | `6CFDAAFC2679E4650162DCF191AF45A1F2EECB1D49AB4FB8571F266FBFBFAFE1` |
| `oasx.exe` | `9B450BD299A3F591380FC1471A1118D877258E9F38A34E222ABB1DB949EB60D2` |

启动页、主页背景、窗口状态和 OAS 目录恢复相关测试共 **67 项通过**；修复版已在本机核对原生窗口可见状态和坐标。启动线稿右下角、主页日志区透明度及应用图标已在界面版本验收时检查。

## 自动更新

应用内「检查更新」指向本仓库所属的发布库 Releases：

```
https://api.github.com/repos/tomoe1-1/OASX/releases/latest
```

比对本机版本与最新 release 的 tag，仅当远端更新时提示。

## 与 1.x 的关系

1.x 与 2.x 属于**同一条发布线**（`tomoe1-1/OASX` Releases），2.x 是视觉层重做：

- 主页加入正面人物科技风**全幅动态背景**，随窗口尺寸自适应铺满
- 启动页线稿**右下角重绘**
- 工作台与日志区**透明度重新校准**
- 恢复**左上角应用图标**

功能逻辑与操作路径未变，从 1.x 升级无学习成本。历史版本见 [Releases](../../releases)。

## 仓库说明

- 本仓库同时是**发行目录**与**源码仓库**
- `logs/`（本机运行日志）、`src/build/`、`src/.dart_tool/` 等已在 `.gitignore` 排除
- `OASX.zip`（发行包）**不入库** —— 它通过 GitHub Release 分发，避免仓库重复存储
