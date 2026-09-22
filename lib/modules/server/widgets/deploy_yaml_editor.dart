import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:styled_widget/styled_widget.dart';

import 'package:oasx/config/design_tokens.dart';
import 'package:oasx/modules/server/models/deploy_yaml_document.dart';
import 'package:oasx/translation/i18n_content.dart';
import 'package:oasx/utils/platform_utils.dart';

part 'deploy_yaml_editor_parts.dart';
part 'deploy_yaml_value_item.dart';
part 'deploy_yaml_help_popup.dart';
part 'deploy_yaml_error_view.dart';

/// Renders deploy.yaml as a structured editor with read-only keys and comments.
class DeployYamlEditor extends StatefulWidget {
  /// Creates one deploy.yaml editor.
  const DeployYamlEditor({
    super.key,
    required this.content,
    required this.maxHeight,
    required this.onSave,
    this.controller,
  });

  /// Source deploy.yaml content.
  final String content;

  /// Maximum editor height from the containing layout.
  final double maxHeight;

  /// Called with serialized YAML when the user saves.
  final ValueChanged<String> onSave;

  /// Optional controller for actions owned by an external header.
  final DeployYamlEditorController? controller;

  @override
  State<DeployYamlEditor> createState() => _DeployYamlEditorState();
}

class _DeployYamlEditorState extends State<DeployYamlEditor> {
  late DeployYamlDocument _document;
  late String _savedContent;
  final Map<int, TextEditingController> _controllers = {};
  final Map<int, FocusNode> _focusNodes = {};
  final Set<int> _collapsedSections = {};

  @override
  void initState() {
    super.initState();
    _savedContent = widget.content;
    _loadDocument();
    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(covariant DeployYamlEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    if (oldWidget.content != widget.content) {
      _savedContent = widget.content;
      _disposeInputs();
      _collapsedSections.clear();
      _loadDocument();
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _disposeInputs();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: widget.maxHeight, child: _buildContent());
  }

  Widget _buildContent() {
    if (_document.hasError) {
      return _DeployYamlErrorView(message: _document.errorMessage!);
    }
    if (!_document.hasEditableValues) {
      return Center(child: Text(I18n.noData.tr));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.smPlus, Spacing.md, Spacing.mdPlus),
      children: [
        for (final node in _visibleCardNodes)
          _DeployYamlNodeView(
            node: node,
            level: 0,
            controllerOf: _controllerOf,
            focusNodeOf: _focusNodeOf,
            onChanged: _updateValue,
            isCollapsed: _isCollapsed,
            onToggleSection: _toggleSection,
          ),
      ],
    );
  }

  Iterable<DeployYamlNode> get _visibleCardNodes {
    final children = _document.roots.expand((node) => node.children).toList();
    return children.isEmpty ? _document.roots : children;
  }

  void _loadDocument() {
    _document = DeployYamlDocument.parse(widget.content);
    for (final valueLine in _document.editableValues) {
      _controllers[valueLine.index] = TextEditingController(
        text: valueLine.value,
      );
      _focusNodes[valueLine.index] = FocusNode();
    }
  }

  TextEditingController _controllerOf(DeployYamlValueLine line) {
    return _controllers[line.index]!;
  }

  FocusNode _focusNodeOf(DeployYamlValueLine line) {
    return _focusNodes[line.index]!;
  }

  void _updateValue(DeployYamlValueLine line, String value) {
    setState(() {
      _document.updateValue(line.index, value);
    });
    widget.controller?._notifyStateChanged();
  }

  bool _isCollapsed(DeployYamlNode node) {
    return _collapsedSections.contains(node.line.index);
  }

  void _toggleSection(DeployYamlNode node) {
    setState(() {
      if (!_collapsedSections.add(node.line.index)) {
        _collapsedSections.remove(node.line.index);
      }
    });
  }

  void _copyYaml() {
    widget.controller?.onCopy?.call(_document.serialize());
  }

  void _saveYaml() {
    final yaml = _document.serialize();
    widget.onSave(yaml);
    _savedContent = yaml;
    widget.controller?.onSave?.call();
    widget.controller?._notifyStateChanged();
  }

  void _disposeInputs() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    _controllers.clear();
    _focusNodes.clear();
  }
}

/// Allows an external header to trigger deploy.yaml editor actions.
class DeployYamlEditorController {
  _DeployYamlEditorState? _state;

  /// Returns whether save/copy actions should be enabled.
  bool get canSave {
    final state = _state;
    return state != null &&
        !state._document.hasError &&
        state._document.hasEditableValues;
  }

  /// Returns whether the editor contains changes not written to deploy.yaml.
  bool get hasUnsavedChanges {
    final state = _state;
    if (state == null || state._document.hasError) {
      return false;
    }
    return state._document.serialize() != state._savedContent;
  }

  /// Called when YAML text is copied.
  void Function(String yaml)? onCopy;

  /// Called after YAML text is saved.
  VoidCallback? onSave;

  /// Called when editor availability changes.
  VoidCallback? onStateChanged;

  /// Copies current YAML text through the external callback.
  void copy() => _state?._copyYaml();

  /// Saves current YAML text through the editor save callback.
  void save() => _state?._saveYaml();

  void _notifyStateChanged() {
    onStateChanged?.call();
  }

  void _attach(_DeployYamlEditorState state) {
    _state = state;
    onStateChanged?.call();
  }

  void _detach(_DeployYamlEditorState state) {
    if (_state == state) {
      _state = null;
      onStateChanged?.call();
    }
  }
}
