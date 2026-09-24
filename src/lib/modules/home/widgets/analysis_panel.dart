import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/modules/home/models/script_analysis_models.dart';
import 'package:oasx/modules/log/log_browser_models.dart';
import 'package:oasx/translation/i18n_content.dart';
import 'package:oasx/config/design_tokens.dart';

class ScriptAnalysisPanel extends StatefulWidget {
  const ScriptAnalysisPanel({super.key, required this.scriptName});

  final String scriptName;

  @override
  State<ScriptAnalysisPanel> createState() => _ScriptAnalysisPanelState();
}

class _ScriptAnalysisPanelState extends State<ScriptAnalysisPanel> {
  List<String> _dates = const [];
  String _dateKey = '';
  ScriptAnalysisSnapshot? _snapshot;
  Map<String, ScriptAnalysisSnapshot> _recentSnapshots = const {};
  String _error = '';
  bool _errorLogs = false;
  List<ScriptErrorLogItem> _errorItems = const [];
  String? _errorId;
  bool _loading = true;
  bool _showClicks = true;
  bool _showSwipes = true;
  bool _showPath = true;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _loadDates();
  }

  @override
  void didUpdateWidget(covariant ScriptAnalysisPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scriptName != widget.scriptName) _loadDates();
  }

  Future<void> _loadDates() async {
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _snapshot = null;
      _error = '';
    });
    try {
      if (_errorLogs) {
        final items = <ScriptErrorLogItem>[];
        String? cursor;
        do {
          final page = await ApiClient().getScriptErrorLogs(
            scriptName: widget.scriptName, cursor: cursor,
          );
          if (!mounted || revision != _revision) return;
          items.addAll(page.items);
          final next = page.nextCursor;
          if (!page.hasMore || next == null || next == cursor) break;
          cursor = next;
        } while (true);
        _errorItems = items;
        _errorId = items.isEmpty ? null : items.first.id;
        await _loadAnalysis(revision);
        return;
      }
      final response = await ApiClient().getScriptStatisticsDates(widget.scriptName);
      if (!mounted || revision != _revision) return;
      _dates = response.dates;
      _dateKey = _dates.isEmpty ? DateFormat('yyyy-MM-dd').format(DateTime.now()) : _dates.first;
      await _loadAnalysis(revision);
    } catch (error) {
      if (!mounted || revision != _revision) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadAnalysis([int? expectedRevision]) async {
    final revision = expectedRevision ?? ++_revision;
    setState(() {
      _loading = true;
      _snapshot = null;
      _error = '';
    });
    try {
      if (_errorLogs) {
        var result = const ScriptAnalysisSnapshot([]);
        if (_errorId != null) {
          final detail = await ApiClient().getScriptErrorLogDetail(
            _errorId!, logLimitBytes: 1048576,
          );
          if (!mounted || revision != _revision) return;
          final fallbackDate = detail.time.length >= 10
              ? detail.time.substring(0, 10)
              : DateFormat('yyyy-MM-dd').format(
                  DateTime.fromMillisecondsSinceEpoch(detail.timestampMs));
          final lines = <ScriptLogLine>[];
          var date = fallbackDate;
          for (final text in detail.log.content.split('\n')) {
            final match = RegExp(r'^(\d{4}-\d{2}-\d{2}) ').firstMatch(text);
            if (match != null) date = match.group(1)!;
            lines.add(ScriptLogLine(
              fileName: '${date}_error.txt', lineNo: lines.length + 1,
              offset: 0, byteLength: text.length, text: text,
              lineTruncated: false,
            ));
          }
          final dates = lines.map((line) => line.fileName.substring(0, 10)).toSet();
          final events = dates.expand((date) => parseScriptAnalysis(lines, date).events).toList()
            ..sort((a, b) => a.time.compareTo(b.time));
          result = ScriptAnalysisSnapshot(events);
          if (detail.log.truncated) {
            _error = '错误日志过大，仅展示已读取部分的点击轨迹（最多 1 MiB）。';
          }
        }
        if (!mounted || revision != _revision) return;
        setState(() { _snapshot = result; _loading = false; });
        return;
      }
      final byKey = <String, ScriptLogLine>{};
      final trendDates = _dates.take(7).toList();
      final oldestRequiredDate = trendDates.isEmpty ? _dateKey : trendDates.last;
      String? cursor;
      for (var page = 0; page < 100; page++) {
        final window = await ApiClient().getScriptLogWindow(
          widget.scriptName,
          cursor: cursor,
          limitLines: 2000,
          limitBytes: 1048576,
        );
        for (final line in window.lines) {
          byKey[line.key] = line;
        }
        final oldestFileName =
            window.lines.isEmpty ? '' : window.lines.first.fileName;
        final oldestDate = oldestFileName.length >= 10
            ? oldestFileName.substring(0, 10)
            : '';
        if (window.reachedStart ||
            !window.hasOlder ||
            (oldestDate.isNotEmpty &&
                oldestDate.compareTo(oldestRequiredDate) < 0)) {
          break;
        }
        cursor = window.olderCursor;
        if (cursor == null || cursor.isEmpty) break;
      }
      final lines = byKey.values.toList()
        ..sort((left, right) {
          final fileCompare = left.fileName.compareTo(right.fileName);
          return fileCompare != 0
              ? fileCompare
              : left.lineNo.compareTo(right.lineNo);
        });
      final result = parseScriptAnalysis(lines, _dateKey);
      final recentSnapshots = <String, ScriptAnalysisSnapshot>{
        for (final date in trendDates) date: parseScriptAnalysis(lines, date),
      };
      if (!mounted || revision != _revision) return;
      setState(() {
        _snapshot = result;
        _recentSnapshots = recentSnapshots;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || revision != _revision) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final snapshot = _snapshot;
    return RefreshIndicator(
      onRefresh: () => _loadAnalysis(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Spacing.xs),
        children: [
          _toolbar(),
          const SizedBox(height: Spacing.md),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: SelectableText(
                  _error,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          if (snapshot == null || snapshot.events.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(child: Text(I18n.homeAnalysisEmpty.tr)),
            )
          else ...[
            if (!_errorLogs) _summary(snapshot),
            if (!_errorLogs) const SizedBox(height: Spacing.md),
            _pathCard(snapshot),
            if (!_errorLogs) ...[
              const SizedBox(height: Spacing.md),
              _densityCard(snapshot),
              const SizedBox(height: Spacing.md),
              _rankingCard(snapshot),
            ],
          ],
        ],
      ),
    );
  }

  Widget _toolbar() {
    return Column(children: [
      Row(children: [
        const Text('日志'),
        const SizedBox(width: Spacing.sm),
        FilterChip(
          label: const Text('错误日志'), selected: _errorLogs,
          onSelected: (value) { _errorLogs = value; _loadDates(); },
        ),
      ]),
      if (_errorLogs) Row(children: [
        Expanded(child: DropdownButton<String>(
          isExpanded: true, value: _errorId,
          hint: const Text('暂无错误日志'),
          items: _errorItems.map((item) => DropdownMenuItem(
            value: item.id, child: Text(item.directory, overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: (value) { if (value == null) return; _errorId = value; _loadAnalysis(); },
        )),
        IconButton(
          onPressed: _loadDates,
          tooltip: I18n.homeConnectionRetryAction.tr,
          icon: const Icon(Icons.refresh),
        ),
      ]) else Row(children: [
      const Icon(Icons.calendar_today_outlined, size: 18),
      const SizedBox(width: Spacing.sm),
      DropdownButton<String>(
        value: _dates.contains(_dateKey) ? _dateKey : null,
        hint: Text(_dateKey),
        items: _dates.map((date) => DropdownMenuItem(value: date, child: Text(date))).toList(),
        onChanged: (date) {
          if (date == null) return;
          _dateKey = date;
          _loadAnalysis();
        },
      ),
      const Spacer(),
      IconButton(
        onPressed: _loadAnalysis,
        tooltip: I18n.homeConnectionRetryAction.tr,
        icon: const Icon(Icons.refresh),
      ),
    ]),
    ]);
  }

  Widget _summary(ScriptAnalysisSnapshot data) {
    return Wrap(spacing: Spacing.xl, runSpacing: Spacing.sm, children: [
      Text('${data.clickCount} ${I18n.homeAnalysisClicks.tr}'),
      Text('${data.randomClickCount} ${I18n.homeAnalysisRandomClicks.tr}'),
      Text('${data.taskCount} ${I18n.homeAnalysisTasks.tr}'),
    ]);
  }

  Widget _pathCard(ScriptAnalysisSnapshot data) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(I18n.homeAnalysisPathTitle.tr, style: Theme.of(context).textTheme.titleMedium),
          Wrap(spacing: Spacing.sm, children: [
            FilterChip(label: Text(I18n.homeAnalysisShowClicks.tr), selected: _showClicks, onSelected: (v) => setState(() => _showClicks = v)),
            FilterChip(label: Text(I18n.homeAnalysisShowSwipes.tr), selected: _showSwipes, onSelected: (v) => setState(() => _showSwipes = v)),
            FilterChip(label: Text(I18n.homeAnalysisShowPath.tr), selected: _showPath, onSelected: (v) => setState(() => _showPath = v)),
          ]),
          const SizedBox(height: Spacing.sm),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: DecoratedBox(
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLowest, borderRadius: BorderRadius.circular(Radii.sm)),
              child: CustomPaint(painter: _ActionPathPainter(data.events, _showClicks, _showSwipes, _showPath, Theme.of(context).colorScheme)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _densityCard(ScriptAnalysisSnapshot data) {
    final randomValues = data.randomClicksPerFourHours;
    final totalValues = data.clicksPerFourHours;
    final dailyValues = _recentSnapshots.entries.toList().reversed.toList();
    const periodLabels = [
      '00–04',
      '04–08',
      '08–12',
      '12–16',
      '16–20',
      '20–24',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: LayoutBuilder(builder: (context, constraints) {
          final meaningless = _titledChart(
            I18n.homeAnalysisDensityTitle.tr,
            _lineChart([
              for (var i = 0; i < randomValues.length; i++)
                FlSpot(i.toDouble(), randomValues[i].toDouble()),
            ], bottomLabels: periodLabels),
          );
          final total = _titledChart(
            I18n.homeAnalysisTotalDensityTitle.tr,
            _lineChart([
              for (var i = 0; i < totalValues.length; i++)
                FlSpot(i.toDouble(), totalValues[i].toDouble()),
            ], bottomLabels: periodLabels),
          );
          final daily = _titledChart(
            I18n.homeAnalysisDailyTrendTitle.tr,
            dailyValues.isEmpty
                ? null
                : _lineChart(
                    [
                      for (var i = 0; i < dailyValues.length; i++)
                        FlSpot(
                          i.toDouble(),
                          dailyValues[i].value.randomClickCount.toDouble(),
                        ),
                    ],
                    bottomLabels: [
                      for (final entry in dailyValues) entry.key.substring(5),
                    ],
                  ),
          );
          if (constraints.maxWidth < 720) {
            return Column(children: [
              meaningless,
              const SizedBox(height: Spacing.lg),
              total,
              const SizedBox(height: Spacing.lg),
              daily,
            ]);
          }
          if (constraints.maxWidth < 1080) {
            return Column(children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: meaningless),
                const SizedBox(width: Spacing.lg),
                Expanded(child: total),
              ]),
              const SizedBox(height: Spacing.lg),
              daily,
            ]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: meaningless),
              const SizedBox(width: Spacing.lg),
              Expanded(child: total),
              const SizedBox(width: Spacing.lg),
              Expanded(child: daily),
            ],
          );
        }),
      ),
    );
  }

  Widget _titledChart(String title, Widget? chart) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Spacing.md),
          SizedBox(
            height: 220,
            child: chart ?? Center(child: Text(I18n.homeStatsChartEmpty.tr)),
          ),
        ],
      );

  Widget _lineChart(List<FlSpot> spots, {List<String> bottomLabels = const []}) {
    return LineChart(LineChartData(
      minY: 0,
      gridData: const FlGridData(show: true),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: bottomLabels.isNotEmpty,
            reservedSize: 28,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index < 0 ||
                  index >= bottomLabels.length ||
                  value != index.toDouble()) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: Spacing.xsPlus),
                child: Text(
                  bottomLabels[index],
                  style: const TextStyle(fontSize: 9),
                ),
              );
            },
          ),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          barWidth: 3,
          dotData: const FlDotData(show: true),
        ),
      ],
    ));
  }

  Widget _rankingCard(ScriptAnalysisSnapshot data) {
    final values = data.clicksByTask.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final shown = values.take(10).toList();
    return _chartCard(
      I18n.homeAnalysisRankingTitle.tr,
      shown.isEmpty
          ? Center(child: Text(I18n.homeStatsChartEmpty.tr))
          : BarChart(BarChartData(
              alignment: BarChartAlignment.spaceAround,
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(), rightTitles: const AxisTitles(),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44, getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= shown.length) return const SizedBox.shrink();
                  final text = shown[index].key.tr;
                  return Padding(padding: const EdgeInsets.only(top: Spacing.xsPlus), child: Transform.rotate(angle: -math.pi / 5, child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9))));
                })),
              ),
              barGroups: [for (var i = 0; i < shown.length; i++) BarChartGroupData(x: i, barRods: [BarChartRodData(toY: shown[i].value.toDouble(), width: 16, borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.xs)))])],
            )),
    );
  }

  Widget _chartCard(String title, Widget chart) => Card(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Spacing.md),
            SizedBox(height: 220, child: chart),
          ]),
        ),
      );
}

class _ActionPathPainter extends CustomPainter {
  _ActionPathPainter(this.events, this.showClicks, this.showSwipes, this.showPath, this.colors);
  final List<ScriptActionEvent> events;
  final bool showClicks;
  final bool showSwipes;
  final bool showPath;
  final ColorScheme colors;

  Offset _point(double x, double y, Size size) => Offset(x / 1280 * size.width, y / 720 * size.height);

  @override
  void paint(Canvas canvas, Size size) {
    final clicks = events.where((e) => e.kind == ScriptActionKind.click).toList();
    if (showPath && clicks.length > 1) {
      final path = Path()..moveTo(_point(clicks.first.startX, clicks.first.startY, size).dx, _point(clicks.first.startX, clicks.first.startY, size).dy);
      for (final event in clicks.skip(1)) {
        final point = _point(event.startX, event.startY, size);
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colors.primary.withValues(alpha: .32)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }
    if (showSwipes) {
      for (final event in events.where((e) => e.kind == ScriptActionKind.swipe)) {
        canvas.drawLine(
          _point(event.startX, event.startY, size),
          _point(event.endX, event.endY, size),
          Paint()
            ..color = colors.tertiary.withValues(alpha: .45)
            ..strokeWidth = 2,
        );
      }
    }
    if (showClicks) {
      for (final event in clicks) {
        canvas.drawCircle(
          _point(event.startX, event.startY, size),
          2,
          Paint()
            ..color = (event.isRandomClick ? colors.error : colors.primary)
                .withValues(alpha: event.isRandomClick ? .6 : .5),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ActionPathPainter oldDelegate) => true;
}
