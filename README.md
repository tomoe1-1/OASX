# OASX 2.x

[OnmyojiAutoScript](https://github.com/tomoe1-1/OnmyojiAutoScript) 的**桌面控制端**，
基于 Flutter Windows 构建。

**当前版本：v2.2.0** —— 统计页重做为可交互 Dashboard：模块可拖动排序与原位放大，顶部常驻全局筛选，图表悬停联动，指标区滚动吸顶，任务行滑出执行详情抽屉。

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
flutter build windows --release --build-name 2.2.0 --build-number 25
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
| version / build | `2.2.0` / `25` |
| 工具链 | Flutter 3.47.5 / Dart 3.13.4 |
| 平台 | windows-x64 |

已核验与实物一致：

| 文件 | SHA256 |
|---|---|
| `data/app.so` | `D498E3026396688276D92B7029576BFB3B3CB806ECDA2E7DBAB563B9FCD20921` |
| `oasx.exe` | `8573D112F169CC01C8909058A9FF17E06DD8350BFABD9519B603C8D7E4F91AF6` |

本机手工测试链（`frontend_server` + `flutter_tester`）跑通全部 21 个测试文件，共 **163 项通过**：新增 9 项 Dashboard 交互测试（拖拽、放大、联动、吸顶、抽屉与 320/480/760 窄窗口布局）、3 项统计控制器测试与 1 项真实统计页渲染检查，其余覆盖当前/下个任务、失败任务选择、实时状态、启动页、主页背景、窗口几何、OAS 目录恢复、标题栏与实际工作台。另有 2 项为**仓库既有失败**（`args_test` 的 multi_enum 解析、Flutter 模板残留的 `widget_test`），与 2.1.0 基线对照失败方式一致，与本次改动无关。Dashboard 尚未以当前后端数据做人工鼠标操作验收。

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

## 2.2.0 Dashboard 交互

统计页重做为可交互 Dashboard，复用原有统计模型、日期与指标选择器、HTTP / SSE 数据流与执行详情组件。

- **拖动模块网格**：按住模块左上角手柄移动到目标位置，其他模块平滑让位、松手吸附，顺序自动保存。
- **模块原位放大**：点击模块标题或右上角放大按钮，底部缩略条切换模块，关闭后恢复原位置与滚动位置。
- **顶部全局筛选**：日期、指标与排序常驻顶部，统计数字滚动过渡、图表平滑更新；日期请求期间保留上一次数据并显示加载进度。
- **图表悬停联动**：悬停任一图表时三个图表同步高亮同一任务，其余任务淡化并显示竖向参考线。
- **指标滚动吸顶**：向下滚动时汇总区连续收缩为单行固定栏，反向滚动连续还原。
- **列表详情抽屉**：点击任务行右侧滑出执行详情，列表缩窄保持可见，上下按钮切换任务。

详细说明见 [Dashboard 2.2.0 实现与验收](./docs/dashboard-2.2.0.md)，布局预览见 `docs/dashboard-preview.png`（测试数据渲染，不代表当前统计记录）。

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
