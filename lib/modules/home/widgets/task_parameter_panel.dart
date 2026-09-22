import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/config/design_tokens.dart';
import 'package:oasx/modules/args/index.dart';
import 'package:oasx/modules/home/controllers/dashboard_controller.dart';
import 'package:oasx/modules/home/models/config_model.dart';
import 'package:oasx/modules/home/widgets/task_json_transfer_actions.dart';
import 'package:oasx/translation/i18n_content.dart';

class TaskParameterPanel extends StatefulWidget {
  const TaskParameterPanel({
    super.key,
    required this.controller,
    required this.scriptModel,
    required this.onBack,
  });

  final HomeDashboardController controller;
  final ScriptModel scriptModel;
  final Future<void> Function() onBack;

  @override
  State<TaskParameterPanel> createState() => _TaskParameterPanelState();
}

class _TaskParameterPanelState extends State<TaskParameterPanel> {
  Future<void>? _loadFuture;
  String _loadKey = '';
  String _loadScopeKey = '';
  String _scriptName = '';
  String _taskName = '';
  int _reloadSerial = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureLoad();
  }

  @override
  void didUpdateWidget(covariant TaskParameterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureLoad();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      _ensureLoad();
      final dragPayload = widget.controller.activeDragPayload.value;
      final canDragGroups = widget.controller.canUseDesktopDragCopy;
      if (_taskName.isEmpty) {
        return const SizedBox.shrink();
      }
      final future = _loadFuture;
      if (future == null) {
        return const SizedBox.shrink();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: I18n.back.tr,
                onPressed: () async {
                  await widget.onBack();
                },
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: Spacing.xs),
              Expanded(
                child: Text(
                  _taskName.tr,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TaskJsonTransferActions(
                configName: _scriptName,
                taskName: _taskName,
                onImported: _reloadCurrentTask,
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Expanded(
            child: FutureBuilder<void>(
              key: ValueKey(_loadKey),
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text('${I18n.error.tr}: ${snapshot.error}'),
                  );
                }
                return Args(
                  key: ValueKey<String>('args-$_loadKey'),
                  scriptName: _scriptName,
                  taskName: _taskName,
                  groupDraggable: canDragGroups,
                  stagingMode: true,
                  activeDragPayload: dragPayload,
                  groupDragPayloadBuilder: canDragGroups
                      ? (groupName) => widget.controller.buildGroupDragPayload(
                          sourceConfig: _scriptName,
                          taskName: _taskName,
                          groupName: groupName,
                        )
                      : null,
                  onGroupDragStarted: widget.controller.startConfigDrag,
                  onGroupDragEnded: widget.controller.clearConfigDrag,
                  onCancel: () async {
                    await widget.controller.closeTaskParameters();
                  },
                );
              },
            ),
          ),
        ],
      );
    });
  }

  void _ensureLoad() {
    final nextTask = widget.controller.activeTaskName.value.trim();
    final nextScript = widget.scriptModel.name.trim();
    final nextScope = widget.controller.linkedScopeScriptsFor(nextScript);
    final argsController = Get.find<ArgsController>();
    final nextScopeKey = '$nextScript/$nextTask';
    if (nextTask.isEmpty || nextScopeKey == _loadScopeKey) {
      if (nextTask.isEmpty) {
        _loadKey = '';
        _loadScopeKey = '';
        _loadFuture = null;
        _scriptName = '';
        _taskName = '';
        argsController.updateScopeScripts(const []);
      } else {
        argsController.updateScopeScripts(nextScope, config: nextScript);
      }
      return;
    }
    _startLoad(nextScript, nextTask, nextScope);
  }

  Future<void> _reloadCurrentTask() async {
    final script = _scriptName.trim();
    final task = _taskName.trim();
    if (script.isEmpty || task.isEmpty) {
      return;
    }
    _reloadSerial++;
    final scope = widget.controller.linkedScopeScriptsFor(script);
    setState(() {
      _startLoad(script, task, scope, force: true);
    });
    await _loadFuture;
  }

  void _startLoad(
    String script,
    String task,
    List<String> scope, {
    bool force = false,
  }) {
    _scriptName = script;
    _taskName = task;
    _loadScopeKey = '$script/$task';
    if (force) {
      _loadKey = '$_loadScopeKey/$_reloadSerial';
    } else {
      _loadKey = _loadScopeKey;
    }
    final argsController = Get.find<ArgsController>();
    _loadFuture = argsController.loadGroups(
      config: _scriptName,
      task: _taskName,
      stagingMode: true,
      scopeScripts: scope,
      saveArgumentOverride: (config, task, group, argument, type, value) {
        return widget.controller.applyLinkedSetArgument(
          config: config,
          task: task,
          group: group,
          argument: argument,
          type: type,
          value: value,
        );
      },
    );
  }
}
