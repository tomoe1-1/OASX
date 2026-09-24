part 'deploy_yaml_line.dart';

/// Describes one editable deploy.yaml document while preserving original text.
class DeployYamlDocument {
  /// Creates one parsed deploy.yaml document.
  DeployYamlDocument({
    required this.lines,
    required this.roots,
    this.errorMessage,
  });

  /// Parses deploy.yaml text into display nodes and editable scalar values.
  factory DeployYamlDocument.parse(String content) {
    try {
      final lines = _parseLines(content);
      final roots = _buildTree(lines);
      return DeployYamlDocument(lines: lines, roots: roots);
    } catch (e) {
      return DeployYamlDocument(
        lines: [DeployYamlRawLine(index: 0, raw: content)],
        roots: const [],
        errorMessage: e.toString(),
      );
    }
  }

  /// Parsed source lines in their original order.
  final List<DeployYamlLine> lines;

  /// Top-level YAML mapping nodes for the editor tree.
  final List<DeployYamlNode> roots;

  /// Parsing error text when the document cannot be edited safely.
  final String? errorMessage;

  /// Returns whether this document has editable content.
  bool get hasEditableValues => editableValues.isNotEmpty;

  /// Returns whether parsing failed.
  bool get hasError => errorMessage != null;

  /// Returns all editable leaf values in source order.
  Iterable<DeployYamlValueLine> get editableValues {
    return lines.whereType<DeployYamlValueLine>();
  }

  /// Updates one editable YAML value by source line index.
  void updateValue(int lineIndex, String value) {
    final line = lines.whereType<DeployYamlValueLine>().firstWhere(
          (item) => item.index == lineIndex,
        );
    line.value = value;
  }

  /// Serializes the document using original lines plus edited leaf values.
  String serialize() {
    return lines.map((line) => line.serialize()).join('\n');
  }
}

List<DeployYamlLine> _parseLines(String content) {
  final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final sourceLines = normalized.split('\n');
  return [
    for (var i = 0; i < sourceLines.length; i++) _parseLine(i, sourceLines[i]),
  ];
}

DeployYamlLine _parseLine(int index, String raw) {
  final trimmedLeft = raw.trimLeft();
  if (trimmedLeft.isEmpty || trimmedLeft.startsWith('#')) {
    return DeployYamlRawLine(index: index, raw: raw);
  }
  final match = RegExp(r'^(\s*)([^:#][^:]*):(.*)$').firstMatch(raw);
  if (match == null) {
    return DeployYamlRawLine(index: index, raw: raw);
  }
  final indent = match.group(1)!.length;
  final key = match.group(2)!.trim();
  final rest = match.group(3)!;
  if (rest.trim().isEmpty) {
    return DeployYamlSectionLine(
      index: index,
      raw: raw,
      indent: indent,
      key: key,
    );
  }
  final valueParts = _splitValueAndSuffix(rest);
  return DeployYamlValueLine(
    index: index,
    raw: raw,
    indent: indent,
    key: key,
    prefix: '${match.group(1)}${match.group(2)}:${valueParts.leadingSpace}',
    originalValue: valueParts.value,
    suffix: valueParts.suffix,
  );
}

_DeployYamlValueParts _splitValueAndSuffix(String rest) {
  final leadingMatch = RegExp(r'^(\s*)').firstMatch(rest)!;
  final leadingSpace = leadingMatch.group(1)!;
  final body = rest.substring(leadingSpace.length);
  final commentIndex = _findInlineCommentIndex(body);
  if (commentIndex < 0) {
    final value = body.trimRight();
    return _DeployYamlValueParts(
      leadingSpace: leadingSpace,
      value: value,
      suffix: body.substring(value.length),
    );
  }
  final value = body.substring(0, commentIndex).trimRight();
  return _DeployYamlValueParts(
    leadingSpace: leadingSpace,
    value: value,
    suffix: body.substring(value.length),
  );
}

int _findInlineCommentIndex(String value) {
  var singleQuoted = false;
  var doubleQuoted = false;
  for (var i = 0; i < value.length; i++) {
    final char = value[i];
    if (char == "'" && !doubleQuoted) {
      singleQuoted = !singleQuoted;
    } else if (char == '"' && !singleQuoted) {
      doubleQuoted = !doubleQuoted;
    } else if (char == '#' && !singleQuoted && !doubleQuoted) {
      if (i == 0 || value[i - 1].trim().isEmpty) {
        return i;
      }
    }
  }
  return -1;
}

List<DeployYamlNode> _buildTree(List<DeployYamlLine> lines) {
  final roots = <DeployYamlNode>[];
  final stack = <DeployYamlNode>[];
  var pendingComments = <DeployYamlRawLine>[];

  for (final line in lines) {
    if (line is DeployYamlRawLine) {
      pendingComments.add(line);
      continue;
    }
    if (line is! DeployYamlSectionLine && line is! DeployYamlValueLine) {
      pendingComments = [];
      continue;
    }
    final indent = line.yamlIndent;
    while (stack.isNotEmpty && stack.last.indent >= indent) {
      stack.removeLast();
    }
    final node = DeployYamlNode(
      key: line.yamlKey,
      indent: indent,
      line: line,
      comments: pendingComments,
    );
    pendingComments = [];
    if (stack.isEmpty) {
      roots.add(node);
    } else {
      stack.last.children.add(node);
    }
    if (line is DeployYamlSectionLine) {
      stack.add(node);
    }
  }

  return roots;
}

class _DeployYamlValueParts {
  const _DeployYamlValueParts({
    required this.leadingSpace,
    required this.value,
    required this.suffix,
  });

  final String leadingSpace;
  final String value;
  final String suffix;
}
