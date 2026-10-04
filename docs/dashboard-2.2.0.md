# Dashboard 2.2.0 实现与验收

Dashboard 接入现有 `ScriptStatisticsPanel`，复用原统计模型、日期与指标选择器、HTTP / SSE 数据流和执行详情组件。新增 `InteractiveStatisticsDashboard` 承担模块几何、动画、悬停与抽屉状态。

模块由主指标、运行次数、战斗次数和任务列表组成。宽窗口采用不等大双列网格，窄窗口改为单列。拖动仅在标题手柄触发，图表和列表仍可正常点击、滚动。模块顺序通过现有 Dashboard 存储适配器保存。放大关闭后恢复模块格位与滚动位置。

筛选条位于滚动区之外，指标区使用 `SliverPersistentHeader` 连续收缩并固定。图表共享任务顺序与悬停任务键，参考线使用相同任务的归一化位置，适配各模块不同宽度。详情抽屉在页面行布局中占据宽度，保证原列表可见，并保留列表滚动状态。

日期切换保留旧快照直到新快照到达；旧数据仍标注自身日期。异步停止旧流后再次检查请求版本，避免快速切换筛选时旧请求覆盖新选择。错误时保留可操作的筛选栏并展示错误信息。缓存同时验证快照身份，避免总运行时间未变时任务次数更新不可见。

验证文件：

- `src/test/interactive_statistics_dashboard_test.dart`：9 项交互与响应式布局测试。
- `src/test/statistics_dashboard_controller_test.dart`：3 项状态测试；可选 Windows 字体渲染截图测试通过 `--dart-define=DASHBOARD_CAPTURE=true` 启用。
- `src/test/home_workbench_resize_test.dart` 与 `src/test/script_analysis_models_test.dart`：9 项已有回归测试。

`dashboard-preview.png` 由真实统计页在测试数据下渲染，用于布局检查。发布版本使用实际后端数据。尚未以用户当前后端数据进行人工鼠标操作验收。
