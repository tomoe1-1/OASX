# OASX 2.x

[OnmyojiAutoScript](https://github.com/tomoe1-1/OnmyojiAutoScript) 的**桌面控制端**，
基于 Flutter Windows 构建。

**当前版本：v2.1.0** —— 失败任务队列中仍处于启用状态的任务继续保留在工作台任务选择列表，任务失败进入重试队列后不再从可选列表消失；手动禁用后不会被重新自动纳入选择。

后续每次修复将补丁版本递增 `0.0.1`，同时递增构建号。

本次启动修复详见 [启动修复说明](./启动修复说明.md)。窗口位置配置异常或显示器断开时恢复为居中窗口；保存的 OAS 目录失效时识别相邻有效安装，无法识别则提供目录选择和重新连接入口。

## 两条获取途径

| 方式 | 适合谁 | 怎么做 |
|---|---|---|
| **下载发行包**（推荐普通用户） | 只想直接用 | 到 [Releases](../../releases/latest) 查看已发布版本；本仓库根目录也包含当前版运行文件 |
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
flutter build windows --release --build-name 2.1.0 --build-number 24
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
| version / build | `2.1.0` / `24` |
| 工具链 | Flutter 3.47.5 / Dart 3.13.4 |
| 平台 | windows-x64 |

已核验与实物一致：

| 文件 | SHA256 |
|---|---|
| `data/app.so` | `470236F804FFCDA66005E67B85EB440485E8BE1802AF9DA6D7D2C0C42038938D` |
| `oasx.exe` | `0C58466DA2961FB752A81D098E2172000101CD49CC1C5FD731495D614C6863FA` |

本机手工测试链（`frontend_server` + `flutter_tester`）跑通全部 19 个测试文件，共 **147 项通过**：覆盖当前/下个任务、失败任务选择、实时状态、启动页、主页背景、窗口几何、OAS 目录恢复、标题栏与实际工作台。另有 2 项为**仓库既有失败**（`args_test` 的 multi_enum 解析、Flutter 模板残留的 `widget_test`），已用改动前的基线副本对照确认与本次改动无关。实际电脑上的右侧残框仍需以安装后的鼠标拖动确认。

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

## 2.1.0 失败任务选择

- 工作台任务选择列表纳入失败任务队列中仍处于启用状态的任务，任务失败进入重试队列后不再从可选列表消失。
- 失败任务被手动禁用后不再被自动重新纳入选择；任务重新入队时恢复可选中状态。
- 详细说明见 [2.1.0 失败任务选择](./docs/2.1.0失败任务选择.md)。

## 2.0.3 背景与跨栏缩放

- 顶部与正文透出同一个全幅动态背景，标题栏使用白色高透明圆角框。
- 继续提高工作台透明度，浅色主面板/右侧/日志内部不透明度为 50%/38%/44%。
- 背景绘制限制在当前软件区域，首次加载不再替换正文父级结构。
- 约束变化或手势取消时清理未完成的分隔条拖动，展开后恢复保存的栏宽。
- 详细说明见 [2.0.3 背景与跨栏缩放](./docs/2.0.3背景与跨栏缩放.md)。

## 2.0.2 缩放与标题栏

- 拖动外缘结束后校正 Flutter 子窗口并重发最终视口尺寸，原生窗口不再使用透明合成底色。
- 标题栏改为深蓝灰渐变、浅色操作图标及青色细线，保留头像、设置、拖动与窗口按钮。
- 本次重编 Windows 原生 runner；只替换 AOT 文件不能包含这项修复。
- 回归说明见 [2.0.2 窗口缩放与标题栏](./docs/2.0.2窗口缩放与标题栏.md)。

原生测试（Visual Studio C++ 与匹配的 Flutter SDK）：

```powershell
./tools/test_window_resize.ps1 -FlutterRoot C:\path\to\flutter
```
## 2.0.1 任务显示修复

- 配置卡分两行显示“当前任务”和“下个任务”，窄面板也保留两行。
- 旧 OAS 后端的 `schedule.running` 可能是调度候选；当前任务由 `Scheduler: Start/End task` 运行日志确认，候选保留在下个任务队列。
- 中途连接时回溯近期运行日志恢复当前任务；无法确认时显示“正在获取”，停止后显示“暂无运行任务”。
- 下个任务保留后端的调度顺序，优先待执行队列，然后等待队列，并排除当前任务。

## 仓库说明

- 本仓库同时是**发行目录**与**源码仓库**
- `logs/`（本机运行日志）、`src/build/`、`src/.dart_tool/` 等已在 `.gitignore` 排除
- `OASX.zip`（发行包）**不入库** —— 它通过 GitHub Release 分发，避免仓库重复存储
