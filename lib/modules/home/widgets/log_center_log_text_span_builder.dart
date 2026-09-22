part of 'log_center_panel.dart';

/// Builds highlighted spans for one log line without selectable text overhead.
class _LogTextSpanBuilder {
  /// Creates one span builder.
  ///
  /// [context] 用于解析语义色 —— 语义色分亮/暗两档，
  /// 必须按当前主题取，不能在构造期锁死。
  const _LogTextSpanBuilder(this.source, this.baseStyle, this.context);

  /// Raw log text.
  final String source;

  /// Base style inherited by all generated spans.
  final TextStyle baseStyle;

  /// Theme context used to resolve semantic colors per brightness.
  final BuildContext context;

  /// Builds a compact set of spans for common log tokens.
  List<InlineSpan> build() {
    final value = _trimTrailingBreaks(source);
    final spans = <InlineSpan>[];
    final tokens = _buildTokens();
    var plainStart = 0;
    var index = 0;
    while (index < value.length) {
      final token = _matchToken(value, index, tokens);
      if (token == null) {
        index++;
        continue;
      }
      if (plainStart < index) {
        spans.add(TextSpan(text: value.substring(plainStart, index)));
      }
      spans.add(token.span);
      // 推进量必须取原始文本中被消费的字符数：级别符号是额外插入的
      // 装饰，不在原文里，用 toPlainText().length 会多算导致解析错位。
      index += token.consumed;
      plainStart = index;
    }
    if (plainStart < value.length) {
      spans.add(TextSpan(text: value.substring(plainStart)));
    }
    return spans.isEmpty ? [TextSpan(text: value)] : spans;
  }

  /// Finds one token match at the current index.
  _MatchedToken? _matchToken(String value, int index, List<_LogToken> tokens) {
    final timestampLength = _timestampLength(value, index);
    if (timestampLength > 0) {
      return _MatchedToken(
        TextSpan(
          text: value.substring(index, index + timestampLength),
          style: baseStyle.copyWith(color: SemanticColors.info(context)),
        ),
        timestampLength,
      );
    }
    for (final token in tokens) {
      if (_matchesToken(value, index, token.text)) {
        final marker = token.marker;
        final style = token.style(baseStyle);
        if (marker == null) {
          return _MatchedToken(
            TextSpan(text: token.text, style: style),
            token.text.length,
          );
        }
        // 级别符号与级别名同色，作为一个整体 span 输出。
        return _MatchedToken(
          TextSpan(
            style: style,
            children: <InlineSpan>[
              TextSpan(text: marker, style: style),
              TextSpan(text: token.text, style: style),
            ],
          ),
          token.text.length,
        );
      }
    }
    return null;
  }

  /// Returns the matched timestamp length at the current index.
  int _timestampLength(String value, int index) {
    const fullLength = 23;
    const timeLength = 12;
    if (_matchesTimestamp(value, index, fullLength, hasDate: true)) {
      return fullLength;
    }
    if (_matchesTimestamp(value, index, timeLength, hasDate: false)) {
      return timeLength;
    }
    return 0;
  }

  /// Checks one timestamp pattern without allocating a regular expression.
  bool _matchesTimestamp(
    String value,
    int index,
    int length, {
    required bool hasDate,
  }) {
    if (index + length > value.length) {
      return false;
    }
    if (!hasDate) {
      return _isTime(value, index);
    }
    return _isDigitRange(value, index, 4) &&
        value[index + 4] == '-' &&
        _isDigitRange(value, index + 5, 2) &&
        value[index + 7] == '-' &&
        _isDigitRange(value, index + 8, 2) &&
        value[index + 10] == ' ' &&
        _isTime(value, index + 11);
  }

  /// Checks one HH:mm:ss.SSS timestamp portion.
  bool _isTime(String value, int index) {
    return _isDigitRange(value, index, 2) &&
        value[index + 2] == ':' &&
        _isDigitRange(value, index + 3, 2) &&
        value[index + 5] == ':' &&
        _isDigitRange(value, index + 6, 2) &&
        value[index + 8] == '.' &&
        _isDigitRange(value, index + 9, 3);
  }

  /// Checks whether a token starts at the current word boundary.
  bool _matchesToken(String value, int index, String token) {
    if (!value.startsWith(token, index)) {
      return false;
    }
    final before = index == 0 ? 32 : value.codeUnitAt(index - 1);
    final afterIndex = index + token.length;
    final after = afterIndex >= value.length
        ? 32
        : value.codeUnitAt(afterIndex);
    return !_isWordCode(before) && !_isWordCode(after);
  }

  /// Checks whether a range contains only digits.
  bool _isDigitRange(String value, int start, int length) {
    for (var offset = 0; offset < length; offset++) {
      final code = value.codeUnitAt(start + offset);
      if (code < 48 || code > 57) {
        return false;
      }
    }
    return true;
  }

  /// Checks whether one code unit is part of an identifier-like word.
  bool _isWordCode(int code) {
    return (code >= 48 && code <= 57) ||
        (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        code == 95;
  }

  /// Removes trailing line breaks without allocating a regular expression.
  String _trimTrailingBreaks(String value) {
    var end = value.length;
    while (end > 0) {
      final codeUnit = value.codeUnitAt(end - 1);
      if (codeUnit != 10 && codeUnit != 13) {
        break;
      }
      end--;
    }
    return end == value.length ? value : value.substring(0, end);
  }

  /// Builds the token table with colors already resolved for the current theme.
  ///
  /// 每个级别都带 [marker] 前缀符号：颜色 + 符号双重区分，
  /// 保证色盲用户与灰度场景下仍能分辨日志级别。
  ///
  /// 颜色在每次 [build] 时解析一次（而非构造期缓存），
  /// 这样主题切换后重新渲染能立刻拿到新档位。
  List<_LogToken> _buildTokens() {
    final info = SemanticColors.info(context);
    final warning = SemanticColors.warning(context);
    final danger = SemanticColors.danger(context);
    final success = SemanticColors.success(context);
    final neutral = SemanticColors.neutral(context);
    return <_LogToken>[
      _LogToken('CRITICAL', danger, marker: '×× ', weight: FontWeight.w600),
      _LogToken('WARNING', warning, marker: '! '),
      _LogToken('ERROR', danger, marker: '× '),
      _LogToken('INFO', info, marker: '· '),
      _LogToken('True', success),
      _LogToken('False', danger),
      _LogToken('None', neutral),
    ];
  }
}

/// Lightweight token descriptor for log rendering.
class _LogToken {
  const _LogToken(this.text, this.color, {this.marker, this.weight});

  /// Token text to match.
  final String text;

  /// Resolved color for the current theme.
  final Color color;

  /// 级别符号前缀：提供颜色之外的第二种区分手段。
  final String? marker;

  /// 可选的额外字重（用于 CRITICAL，让最严重的级别在灰度下也更突出）。
  final FontWeight? weight;

  /// Applies this token's color (and weight) on top of the inherited base.
  TextStyle style(TextStyle base) =>
      base.copyWith(color: color, fontWeight: weight);
}

/// A matched token together with how many source characters it consumed.
///
/// [consumed] is tracked separately from the rendered span because markers are
/// inserted decoration: they appear on screen but do not exist in the raw log
/// line, so they must never advance the scan index.
class _MatchedToken {
  const _MatchedToken(this.span, this.consumed);

  /// Rendered span for the match.
  final TextSpan span;

  /// Number of characters consumed from the source string.
  final int consumed;
}
