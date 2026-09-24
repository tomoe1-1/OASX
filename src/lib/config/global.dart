class GlobalVar {
  static final GlobalVar _instance = GlobalVar._internal();
  factory GlobalVar() => _instance;
  GlobalVar._internal();

  /// 兜底展示版本号。
  ///
  /// 发布构建下真正的版本来自 `package_info_plus`（读 pubspec 的 `version:`），
  /// 这个常量只在 settings 页首次渲染、或 debug 模式下被用到。
  /// **必须与 pubspec.yaml 保持同步**，否则界面上会闪现一个过期版本号。
  static String version = "v1.0.0";
}
