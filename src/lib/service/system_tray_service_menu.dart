part of 'system_tray_service.dart';

extension SystemTrayServiceMenuX on SystemTrayService {
  List<SubMenu> buildScriptMenuGroups() {
    if (!Get.isRegistered<ScriptService>()) {
      return _emptyScriptMenuGroups();
    }
    final scriptService = Get.find<ScriptService>();
    if (scriptService.scriptModelMap.isEmpty ||
        scriptService.scriptModelMap.values.isEmpty) {
      return _emptyScriptMenuGroups();
    }
    final scripts = _orderedScripts(scriptService);
    return [
      _buildScriptGroup(
        label: I18n.trayRunningConfigs.tr,
        scripts: scripts.where(_isRunningScript),
        startOnClick: false,
      ),
      _buildScriptGroup(
        label: I18n.trayStoppedConfigs.tr,
        scripts: scripts.where(_isStoppedScript),
        startOnClick: true,
      ),
      _buildScriptGroup(
        label: I18n.trayAbnormalConfigs.tr,
        scripts: scripts.where(_isAbnormalScript),
        startOnClick: true,
      ),
    ];
  }

  List<SubMenu> _emptyScriptMenuGroups() {
    return [
      _emptyScriptGroup(I18n.trayRunningConfigs.tr),
      _emptyScriptGroup(I18n.trayStoppedConfigs.tr),
      _emptyScriptGroup(I18n.trayAbnormalConfigs.tr),
    ];
  }

  SubMenu _emptyScriptGroup(String label) {
    return SubMenu(
      label: label,
      children: [MenuItemLabel(label: I18n.empty.tr)],
    );
  }

  SubMenu _buildScriptGroup({
    required String label,
    required Iterable<ScriptModel> scripts,
    required bool startOnClick,
  }) {
    final children = scripts
        .map(
          (script) => MenuItemLabel(
            label: buildScriptMenuLabel(script),
            onClicked: (_) => _toggleScript(script.name, startOnClick),
          ),
        )
        .toList();
    return SubMenu(
      label: label,
      children: children.isEmpty
          ? [MenuItemLabel(label: I18n.empty.tr)]
          : children,
    );
  }

  List<ScriptModel> _orderedScripts(ScriptService scriptService) {
    final scripts = <ScriptModel>[];
    for (final name in scriptService.scriptOrderList) {
      final script = scriptService.findScriptModel(name);
      if (script != null) scripts.add(script);
    }
    final knownNames = scripts.map((script) => script.name).toSet();
    scripts.addAll(
      scriptService.scriptModelMap.values.where(
        (script) => !knownNames.contains(script.name),
      ),
    );
    return scripts;
  }

  bool _isRunningScript(ScriptModel script) {
    return script.state.value == ScriptState.running;
  }

  bool _isStoppedScript(ScriptModel script) {
    return script.state.value == ScriptState.inactive;
  }

  bool _isAbnormalScript(ScriptModel script) {
    return script.state.value == ScriptState.warning ||
        script.state.value == ScriptState.updating;
  }

  Future<void> _toggleScript(String scriptName, bool startOnClick) async {
    final scriptService = Get.find<ScriptService>();
    if (startOnClick) {
      await scriptService.startScript(scriptName);
      return;
    }
    await scriptService.stopScript(scriptName);
  }

  String buildScriptMenuLabel(ScriptModel scriptModel) {
    final taskLabel = _firstTaskLabel(scriptModel);
    if (taskLabel.isEmpty) return scriptModel.name;
    return '${scriptModel.name} - $taskLabel';
  }

  String _firstTaskLabel(ScriptModel scriptModel) {
    final runningName = scriptModel.runningTask.value.taskName.value.trim();
    if (runningName.isNotEmpty) return runningName.tr;
    for (final task in scriptModel.pendingTaskList) {
      final taskName = task.taskName.value.trim();
      if (taskName.isNotEmpty) return taskName.tr;
    }
    for (final task in scriptModel.waitingTaskList) {
      final taskName = task.taskName.value.trim();
      if (taskName.isEmpty) continue;
      final nextRun = _timeOfDayText(task.nextRun.value);
      return nextRun.isEmpty ? taskName.tr : '${taskName.tr} $nextRun';
    }
    return '';
  }

  String _timeOfDayText(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return normalized;
    final parts = normalized.split(' ');
    return parts.isEmpty ? normalized : parts.last;
  }
}
