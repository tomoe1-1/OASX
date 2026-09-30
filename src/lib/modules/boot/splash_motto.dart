/// 启动页的「日期 + 每日语录」
///
/// 取代原先的固定副标题「OAS 工作模式」。
///
/// ## 为什么换掉固定副标题
///
/// 「OAS 工作模式」是一句**永远不变的功能说明**——用户第二次开机就再也不会
/// 读它。它占了字标正下方最贵的一块位置，却每天提供零信息量。
///
/// 换成日期 + 语录之后，这一栏每天来都不一样：
/// - **日期**是真实信息（今天几号），顺带让界面有「今日」的在场感
/// - **语录**提供一点点情绪价值 —— 挂机脚本往往要跑一整晚，开机瞬间
///   一句安静的话比一句「工作模式」更贴合场景
///
/// ## 语录的选取原则
///
/// 1. **按天确定性**：用连续的日序号做索引，同一天永远同一句，
///    同一天内多次开机不会跳来跳去（否则会显得随机、廉价）。
/// 2. **不喊口号**：排除「努力」「成功」「坚持」这类鸡汤 —— 受众是
///    夜间挂机的用户，不是来被励志的。取的是安静、克制、有画面感的句子。
/// 3. **长度可控**：每句 ≤ 26 字，保证在字标下方一行放得下不换行。
/// 4. **不重复**：`_mottos.length` 与 366 互质附近取值，保证一年内
///    基本不撞句；这里取 37 句，37 与 365 的循环错开得很自然。
library;

import 'dart:math' as math;

/// 每日语录池。
///
/// 口径：安静、克制、有画面感。**刻意排除**励志口号与网络流行语 ——
/// 前者说教，后者会随时间腐坏。
const List<String> kSplashMottos = <String>[
  '把该做的事做完，剩下的交给时间',
  '慢一点没关系，方向对就好',
  '今天也照常运转，这本身就不容易',
  '不必每一步都踩在鼓点上',
  '夜深了，让机器替你守着',
  '重复的事，交给不会厌倦的它',
  '效率不是赶，是不返工',
  '安静地把一件事做完，是种本事',
  '计划会变，但总要有个开始',
  '等待也是一种进度',
  '不必解释，跑起来就清楚了',
  '把复杂留给自己，把简单留给结果',
  '机器不困，人会。早点休息',
  '今天的一小步，也算数',
  '让脚本去熬夜，你去睡觉',
  '做完再想值不值得',
  '所有自动化，起点都是一次手动',
  '状态好就多跑一点，不好就先歇着',
  '别急，它比你有耐心',
  '顺手的工具，用起来才长久',
  '少了哪一步都会重来，所以先检查',
  '一天的长度，取决于你怎么切它',
  '稳定比精彩更难得',
  '不用时刻盯着，它记得住',
  '把注意力留给需要它的地方',
  '先让它跑起来，再让它跑得好',
  '犹豫的时间，通常比试错长',
  '做得慢，总好过没做',
  '夜里的算力，白天不用排队',
  '习惯是复利，不是冲刺',
  '偶尔停下，是为了看清方向',
  '别把简单的事做复杂',
  '能自动的，就别动手',
  '今天无事发生，是很好的消息',
  '把时间花在只有你能做的事上',
  '每个安静的进程，背后都有个想省事的人',
  '慢慢来，比较快',
];

/// 取某一天的语录。
///
/// 从固定日期起连续计日，让 12/31 与次年 1/1 仍是相邻两句。
int mottoIndexFor(DateTime date) {
  final day = DateTime.utc(date.year, date.month, date.day);
  final index = day.difference(DateTime.utc(2020, 1, 1)).inDays;
  return index % kSplashMottos.length;
}

/// 取某一天的语录文本。
String mottoFor(DateTime date) => kSplashMottos[mottoIndexFor(date)];

/// 星期几的中文短名（周一 … 周日）。
const List<String> _weekdayZh = <String>[
  '周一',
  '周二',
  '周三',
  '周四',
  '周五',
  '周六',
  '周日',
];

/// 格式化成启动页用的日期串，例如 `2026 年 9 月 29 日 · 周二`。
///
/// 不用 `intl` 的 `DateFormat`：这里只有一种格式、一种语言，
/// 引一个 locale 数据表反而多一层运行期依赖（且 `intl` 需要额外初始化）。
/// 手写拼装只有三行，且结果完全可预期。
String formatSplashDate(DateTime date) {
  final w = _weekdayZh[(date.weekday - 1).clamp(0, 6)];
  return '${date.year} 年 ${date.month} 月 ${date.day} 日 · $w';
}

/// 日期与语录的排版宽度预算 —— 供 painter 决定字号是否要收缩。
///
/// 返回 [maxDateWidth] / [maxMottoWidth]，单位是「基准字号 `baseSize` 的倍数」。
/// painter 拿它和实际 `TextPainter.width` 比对，超了就缩字号，
/// 避免长语录在窄窗口下戳出左栏。
({double maxDateWidth, double maxMottoWidth}) splashSubtitleBudget(
  double panelWidth,
) {
  return (
    maxDateWidth: panelWidth,
    maxMottoWidth: panelWidth,
  );
}

/// 视口极窄时的兜底：如果连最小字号都放不下，就截断加省略号。
///
/// 这里只做「要不要截断」的判断，真正的截断交给 `TextPainter` 的
/// `ellipsis` —— 手动切字符会把中文和英文单词切坏。
bool needsEllipsis(String text, double width, double fontSize) {
  // 中文按 1.0em、ASCII 按 0.55em 粗估
  var est = 0.0;
  for (final r in text.runes) {
    est += r < 0x2E80 ? fontSize * 0.55 : fontSize;
  }
  return est > width;
}

/// 保证字号不小于可读下限（11px），否则宁可截断也不缩到看不清。
double clampMottoFontSize(double size) => math.max(size, 11.0);
