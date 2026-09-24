part of 'log_center_panel.dart';

/// Shared lightweight rich log text renderer.
class LogCenterLogText extends StatelessWidget {
  /// Creates one log text row.
  const LogCenterLogText({
    super.key,
    required this.line,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.softWrap = false,
  });

  /// Raw log text.
  final String line;

  /// Maximum visible lines.
  final int? maxLines;

  /// Overflow behavior for the rendered line.
  final TextOverflow overflow;

  /// Whether the text can wrap.
  final bool softWrap;

  @override
  Widget build(BuildContext context) {
    final style = _selectStyle(context);
    final richText = line.length <= kErrorLogPlainTextThreshold;
    final selectionStyle = DefaultSelectionStyle.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: RichText(
        text: TextSpan(
          style: style,
          children: richText
              ? _LogTextSpanBuilder(line, style, context).build()
              : [TextSpan(text: line)],
        ),
        selectionRegistrar: SelectionContainer.maybeOf(context),
        selectionColor:
            selectionStyle.selectionColor ??
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.28),
        maxLines: maxLines,
        overflow: overflow,
        softWrap: softWrap,
      ),
    );
  }

  /// Selects the monospace-friendly log text style.
  TextStyle _selectStyle(BuildContext context) {
    return Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      height: 1.4,
    );
  }
}
