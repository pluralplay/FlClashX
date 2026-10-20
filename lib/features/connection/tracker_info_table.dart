import 'dart:math';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tracker_info_item.dart';
import 'tracker_info_visuals.dart';

const _fullLiveTableWidth = 1200.0;

List<RecordColumn<TrackerInfo>> trackerInfoColumns(
  BuildContext context, {
  required double width,
  required bool isLive,
  Widget? Function(TrackerInfo trackerInfo)? actionBuilder,
}) {
  final appLocalizations = context.appLocalizations;
  final wide = width >= recordWideTableWidth;
  // A live table spends its first extra width on the totals.
  final detailed = wide && (!isLive || width >= _fullLiveTableWidth);
  double totalWidth(String label) => max(88, recordHeaderWidth(context, label));
  return [
    if (!isLive)
      RecordColumn(
        TableColumn('time', appLocalizations.time, width: 80),
        cell: (_, info) =>
            RecordCellText(info.start.showTime.trim(), muted: true),
        sortKey: (info) => info.start,
        descendingFirst: true,
      ),
    RecordColumn(
      TableColumn('process', appLocalizations.process, width: wide ? 160 : 140),
      cell: (_, info) => _ProcessCell(info),
      sortKey: (info) => info.progressText.toLowerCase(),
    ),
    RecordColumn(
      TableColumn('target', appLocalizations.target, flex: wide ? 1.4 : 1.3),
      cell: (_, info) => _TargetCell(info),
      sortKey: (info) => info.title.toLowerCase(),
    ),
    if (detailed)
      RecordColumn(
        TableColumn(
          'protocol',
          appLocalizations.protocol,
          width: max(56, recordHeaderWidth(context, appLocalizations.protocol)),
        ),
        cell: (_, info) => Align(
          alignment: AlignmentDirectional.centerStart,
          child: NetworkLabel(info.metadata.network),
        ),
        sortKey: (info) => info.metadata.network.toLowerCase(),
      ),
    if (wide || !isLive)
      RecordColumn(
        TableColumn('rule', appLocalizations.rule, flex: 1),
        cell: (_, info) => info.rule.isEmpty
            ? const RecordCellText('')
            : RuleLabel(
                info,
                onPressed: () =>
                    context.commonScaffoldState?.addKeyword(info.rule),
              ),
        sortKey: (info) => '${info.rule} ${info.rulePayload}'.toLowerCase(),
      ),
    RecordColumn(
      TableColumn('exit', appLocalizations.outboundExit, width: 120),
      cell: (_, info) => _ExitChip(exit: info.chains.firstOrNull ?? ''),
      sortKey: (info) => (info.chains.firstOrNull ?? '').toLowerCase(),
    ),
    if (isLive) ...[
      _amountColumn(
        'downloadSpeed',
        appLocalizations.download,
        (info) => info.downloadSpeed ?? 0,
        perSecond: true,
        activeColor: (colorScheme) => colorScheme.primary,
      ),
      _amountColumn(
        'uploadSpeed',
        appLocalizations.upload,
        (info) => info.uploadSpeed ?? 0,
        perSecond: true,
        activeColor: (colorScheme) => colorScheme.tertiary,
      ),
    ],
    if (isLive && wide) ...[
      _amountColumn(
        'download',
        appLocalizations.totalDownload,
        (info) => info.download,
        width: totalWidth(appLocalizations.totalDownload),
      ),
      _amountColumn(
        'upload',
        appLocalizations.totalUpload,
        (info) => info.upload,
        width: totalWidth(appLocalizations.totalUpload),
      ),
    ] else if (wide) ...[
      _amountColumn(
        'download',
        appLocalizations.download,
        (info) => info.download,
      ),
      _amountColumn('upload', appLocalizations.upload, (info) => info.upload),
    ] else
      _amountColumn(
        'traffic',
        appLocalizations.traffic,
        (info) => info.upload + info.download,
        width: 88,
      ),
    if (isLive && detailed)
      RecordColumn(
        TableColumn(
          'duration',
          appLocalizations.duration,
          width: 80,
          end: true,
        ),
        cell: (_, info) => RecordCellText(
          trackerDurationText(DateTime.now().difference(info.start)),
          muted: true,
        ),
        sortKey: (info) => -info.start.microsecondsSinceEpoch,
        descendingFirst: true,
      ),
    if (actionBuilder != null)
      RecordColumn(
        const TableColumn('action', '', width: 44, resizable: false),
        cell: (_, info) => actionBuilder(info) ?? const SizedBox.shrink(),
      ),
  ];
}

RecordColumn<TrackerInfo> _amountColumn(
  String id,
  String label,
  int Function(TrackerInfo info) amountOf, {
  double width = 100,
  bool perSecond = false,
  Color Function(ColorScheme colorScheme)? activeColor,
}) {
  return RecordColumn(
    TableColumn(id, label, width: width, end: true),
    cell: (context, info) {
      final amount = amountOf(info);
      final text = perSecond ? '${amount.traffic.show}/s' : amount.traffic.show;
      if (activeColor != null && amount > 0) {
        return Text(
          text,
          style: TextStyle(color: activeColor(context.colorScheme)),
        );
      }
      return RecordCellText(text, muted: perSecond && amount == 0);
    },
    sortKey: amountOf,
    descendingFirst: true,
  );
}

class _ProcessCell extends ConsumerWidget {
  final TrackerInfo info;

  const _ProcessCell(this.info);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final process = info.metadata.process;
    final showIcon =
        system.isAndroid &&
        process.isNotEmpty &&
        ref.watch(
          patchClashConfigProvider.select(
            (state) => state.findProcessMode == FindProcessMode.always,
          ),
        );
    if (!showIcon) {
      return RecordCellText(info.progressText);
    }
    return Row(
      spacing: 6,
      children: [
        ClipRSuperellipse(
          borderRadius: AppRadius.all(4),
          child: PackageIcon(packageName: process, size: 18),
        ),
        Flexible(child: RecordCellText(info.progressText)),
      ],
    );
  }
}

class _TargetCell extends StatelessWidget {
  final TrackerInfo info;

  const _TargetCell(this.info);

  @override
  Widget build(BuildContext context) {
    final country = destinationCountryOf(info);
    if (country == null) {
      return TrackerTargetText(info);
    }
    return Row(
      spacing: 6,
      children: [
        CountryMark(countryCode: country, size: 14),
        Flexible(child: TrackerTargetText(info)),
      ],
    );
  }
}

String trackerDurationText(Duration duration) {
  final seconds = duration.inSeconds;
  if (seconds < 60) {
    return '${seconds < 0 ? 0 : seconds} s';
  }
  final minutes = seconds / 60;
  if (minutes < 60) {
    return '${minutes < 10 ? minutes.toStringAsFixed(1) : minutes.round()} min';
  }
  return '${(minutes / 60).toStringAsFixed(1)} h';
}

class TrackerInfoTableRow extends StatelessWidget {
  final TrackerInfo trackerInfo;
  final RecordTable<TrackerInfo> table;
  final bool striped;
  final String detailTitle;

  const TrackerInfoTableRow({
    super.key,
    required this.trackerInfo,
    required this.table,
    required this.striped,
    required this.detailTitle,
  });

  @override
  Widget build(BuildContext context) {
    return RecordTableRow(
      table: table,
      striped: striped,
      onTap: () => showTrackerInfoDetail(context, trackerInfo, detailTitle),
      cells: table.cellsOf(context, trackerInfo),
    );
  }
}

class _ExitChip extends StatelessWidget {
  final String exit;

  const _ExitChip({required this.exit});

  @override
  Widget build(BuildContext context) {
    if (exit.isEmpty) {
      return const RecordCellText('');
    }
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: OutboundChip(
        label: exit,
        onPressed: () => context.commonScaffoldState?.addKeyword(exit),
      ),
    );
  }
}

class TrackerTargetText extends StatelessWidget {
  final TrackerInfo trackerInfo;

  const TrackerTargetText(this.trackerInfo, {super.key});

  @override
  Widget build(BuildContext context) {
    final port = trackerInfo.metadata.destinationPort;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: trackerInfo.title),
          if (port.isNotEmpty)
            TextSpan(
              text: ':$port',
              style: TextStyle(color: context.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class TrackerRuleText extends StatelessWidget {
  final TrackerInfo trackerInfo;

  const TrackerRuleText(this.trackerInfo, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: trackerInfo.rule,
            style: TextStyle(color: context.colorScheme.onSurfaceVariant),
          ),
          if (trackerInfo.rulePayload.isNotEmpty)
            TextSpan(text: ' ${trackerInfo.rulePayload}'),
        ],
      ),
    );
  }
}
