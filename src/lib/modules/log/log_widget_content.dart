part of 'log_widget.dart';

class LogContent extends StatelessWidget {
  const LogContent({
    super.key,
    required this.controller,
    required this.scrollController,
    required this.onUserScroll,
  });

  final LogMixin controller;
  final ScrollController scrollController;
  final Function() onUserScroll;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, Spacing.smPlus),
      child: NotificationListener<UserScrollNotification>(
        onNotification: (notification) {
          onUserScroll();
          return false;
        },
        child: Obx(
          () => ListView.builder(
            controller: scrollController,
            itemCount: controller.logs.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              // 日志列表是整个界面里重绘最频繁的区域（运行中每 120ms 刷新一次）。
              // 每行都是一段 EasyRichText，排版代价不低；加一层 RepaintBoundary
              // 可以把重绘限制在真正变化的行上，避免整屏日志跟着一起重绘。
              child: RepaintBoundary(
                child: EasyRichText(
                  controller.logs[index],
                  patternList: _buildPatterns(context),
                  selectable: true,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  defaultStyle: _selectStyle(context),
                ),
              ),
            ),
          ).paddingAll(Spacing.smPlus),
        ),
      ),
    ).constrained(width: double.infinity, height: double.infinity);
  }

  List<EasyRichTextPattern> _buildPatterns(BuildContext context) {
    // 日志级别：颜色 + 前缀符号双重区分，避免仅靠颜色传达信息
    // （色盲用户与灰度场景下仍需可读）。
    //
    // 颜色按当前亮/暗主题解析后复用到 style 与 prefixInlineSpan，
    // 避免同一处写两遍导致两档取值不一致。
    final info = SemanticColors.info(context);
    final warning = SemanticColors.warning(context);
    final danger = SemanticColors.danger(context);
    final success = SemanticColors.success(context);
    final neutral = SemanticColors.neutral(context);
    const tabular = [FontFeature.tabularFigures()];

    TextStyle level(Color color, {FontWeight? weight}) => TextStyle(
          color: color,
          fontWeight: weight,
          fontFeatures: tabular,
        );

    return [
      EasyRichTextPattern(
        targetString: 'INFO',
        style: level(info),
        prefixInlineSpan: TextSpan(style: level(info), text: '· '),
        suffixInlineSpan: const TextSpan(
          style: TextStyle(fontFeatures: tabular),
          text: '      ',
        ),
      ),
      EasyRichTextPattern(
        targetString: 'WARNING',
        style: level(warning),
        prefixInlineSpan: TextSpan(style: level(warning), text: '! '),
      ),
      EasyRichTextPattern(
        targetString: 'ERROR',
        style: level(danger),
        prefixInlineSpan: TextSpan(style: level(danger), text: '× '),
        suffixInlineSpan: const TextSpan(
          style: TextStyle(fontFeatures: tabular),
          text: '    ',
        ),
      ),
      EasyRichTextPattern(
        targetString: 'CRITICAL',
        style: level(danger, weight: FontWeight.w600),
        prefixInlineSpan: TextSpan(
          style: level(danger, weight: FontWeight.w600),
          text: '×× ',
        ),
        suffixInlineSpan: const TextSpan(text: '   '),
      ),
      EasyRichTextPattern(
        targetString: r'(\d{2}:\d{2}:\d{2}\.\d{3})',
        style: level(info),
      ),
      const EasyRichTextPattern(
        targetString: r'[\{\[\(\)\]\}]',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      EasyRichTextPattern(
        targetString: 'True',
        style: TextStyle(color: success),
      ),
      EasyRichTextPattern(
        targetString: 'False',
        style: TextStyle(color: danger),
      ),
      EasyRichTextPattern(
        targetString: 'None',
        style: TextStyle(color: neutral),
      ),
      EasyRichTextPattern(
        targetString: r'(某喵*某喵)|(~~*~~)',
        style: TextStyle(color: success),
      ),
    ];
  }

  TextStyle _selectStyle(BuildContext context) {
    return context.mediaQuery.orientation == Orientation.portrait
        ? Theme.of(context).textTheme.bodySmall!
        : Theme.of(context).textTheme.titleSmall!;
  }
}
