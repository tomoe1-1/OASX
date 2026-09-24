part of 'deploy_yaml_document.dart';

/// Base type for one original deploy.yaml line.
abstract class DeployYamlLine {
  /// Creates one source line.
  const DeployYamlLine({required this.index, required this.raw});

  /// Zero-based source line index.
  final int index;

  /// Original source line.
  final String raw;

  /// Returns this line as YAML text.
  String serialize();
}

/// Preserves comments, blank lines, and unsupported YAML rows.
class DeployYamlRawLine extends DeployYamlLine {
  /// Creates one immutable raw YAML line.
  const DeployYamlRawLine({required super.index, required super.raw});

  @override
  String serialize() => raw;
}

/// Represents a mapping key that owns child YAML values.
class DeployYamlSectionLine extends DeployYamlLine {
  /// Creates one section title line.
  const DeployYamlSectionLine({
    required super.index,
    required super.raw,
    required this.indent,
    required this.key,
  });

  /// Leading space count.
  final int indent;

  /// YAML mapping key.
  final String key;

  @override
  String serialize() => raw;
}

/// Represents one editable YAML mapping value.
class DeployYamlValueLine extends DeployYamlLine {
  /// Creates one editable scalar line.
  DeployYamlValueLine({
    required super.index,
    required super.raw,
    required this.indent,
    required this.key,
    required this.prefix,
    required this.originalValue,
    required this.suffix,
  }) : value = originalValue;

  /// Leading space count.
  final int indent;

  /// YAML mapping key.
  final String key;

  /// Text before the editable value, including indentation and `key:`.
  final String prefix;

  /// Value from the original source line.
  final String originalValue;

  /// Inline comment suffix preserved after the value.
  final String suffix;

  /// Current editable value.
  String value;

  /// Returns whether this scalar value is a YAML bool.
  bool get isBoolean {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' || normalized == 'false';
  }

  @override
  String serialize() => '$prefix$value$suffix';
}

/// Display node for one YAML mapping key.
class DeployYamlNode {
  /// Creates a section or leaf node.
  DeployYamlNode({
    required this.key,
    required this.indent,
    required this.line,
    required this.comments,
  });

  /// YAML mapping key.
  final String key;

  /// Leading space count from the source line.
  final int indent;

  /// Source line backing this node.
  final DeployYamlLine line;

  /// Consecutive comments and blank lines immediately above this node.
  final List<DeployYamlRawLine> comments;

  /// Child mapping nodes.
  final List<DeployYamlNode> children = [];

  /// Editable scalar line for leaf nodes.
  DeployYamlValueLine? get valueLine {
    final item = line;
    return item is DeployYamlValueLine ? item : null;
  }
}

extension _DeployYamlMappingLine on DeployYamlLine {
  int get yamlIndent {
    final line = this;
    if (line is DeployYamlSectionLine) {
      return line.indent;
    }
    if (line is DeployYamlValueLine) {
      return line.indent;
    }
    return 0;
  }

  String get yamlKey {
    final line = this;
    if (line is DeployYamlSectionLine) {
      return line.key;
    }
    if (line is DeployYamlValueLine) {
      return line.key;
    }
    return '';
  }
}
