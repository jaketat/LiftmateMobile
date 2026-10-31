// T6: tab "Báo hỏng" của tài xế, kiểu iOS (Cupertino + Liquid Glass):
// - Tiêu đề lớn co lại khi cuộn, thanh trên làm mờ tăng dần (IosPage).
// - Thẻ kính "Xe gặp sự cố?" với nút đỏ lớn để báo ngay.
// - Danh sách 50 báo gần nhất dạng "inset grouped"; bấm một báo thì mở bảng xem tiến độ
//   (Đã gửi → Điều phối đã nhận → Đã xử lý), ảnh và lời nhắn xử lý. Giống thẻ "Báo hỏng của tôi" trên web.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/ios.dart';
import 'maintenance_api.dart';
import 'maintenance_providers.dart';

Color _statusColor(String status) {
  switch (status) {
    case 'Resolved':
      return IosColors.green;
    case 'Acknowledged':
      return IosColors.blue;
    default:
      return IosColors.orange;
  }
}

Color severityColor(String severity) => severity == 'MustStop' ? IosColors.red : IosColors.orange;

IconData severityIcon(String severity) =>
    severity == 'MustStop' ? Icons.dangerous_rounded : Icons.warning_rounded;

class MyBreakdownsScreen extends ConsumerWidget {
  const MyBreakdownsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<BreakdownReport>> reportsValue = ref.watch(myBreakdownsProvider);

    final List<Widget> slivers = <Widget>[
      SliverToBoxAdapter(
        child: _ReportHero(onReport: () => context.push('/driver/breakdowns/new')),
      ),
    ];

    slivers.add(reportsValue.when(
      data: (List<BreakdownReport> reports) {
        if (reports.isEmpty) {
          return const SliverToBoxAdapter(child: _EmptyState());
        }
        return SliverToBoxAdapter(
          child: IosGroup(
            header: t('breakdowns.recent'),
            dividerIndent: 62,
            children: <Widget>[
              for (final BreakdownReport report in reports)
                _ReportRow(report: report, onTap: () => showBreakdownSheet(context, report)),
            ],
          ),
        );
      },
      loading: () => const SliverToBoxAdapter(
        child: Padding(padding: EdgeInsets.only(top: 60), child: CupertinoActivityIndicator(radius: 13)),
      ),
      error: (Object error, StackTrace _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 40, 32, 0),
          child: Column(
            children: <Widget>[
              Text(
                errorMessage(error),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: IosColors.secondaryLabel),
              ),
              CupertinoButton(
                onPressed: () => ref.invalidate(myBreakdownsProvider),
                child: Text(t('common.retry')),
              ),
            ],
          ),
        ),
      ),
    ));


    return IosPage(
      title: t('breakdowns.title'),
      showBack: false,
      glow: IosColors.red,
      onRefresh: () => ref.refresh(myBreakdownsProvider.future),
      slivers: slivers,
    );
  }
}

/// Thẻ kính trên cùng: lời mời báo hỏng và nút đỏ lớn
class _ReportHero extends StatelessWidget {
  final VoidCallback onReport;

  const _ReportHero({required this.onReport});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      child: Glass(
        opacity: 0.55,
        borderRadius: BorderRadius.circular(28),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const IosIconBadge(icon: Icons.car_crash_rounded, color: IosColors.red, size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        t('breakdowns.heroTitle'),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text, letterSpacing: -0.3),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t('breakdowns.heroMessage'),
                        style: const TextStyle(fontSize: 14, color: IosColors.secondaryLabel, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            IosPillButton(
              label: t('breakdowns.report'),
              icon: Icons.report_rounded,
              color: IosColors.red,
              onPressed: onReport,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 24, 40, 0),
      child: Column(
        children: <Widget>[
          const Icon(Icons.verified_rounded, size: 56, color: IosColors.green),
          const SizedBox(height: 12),
          Text(
            t('breakdowns.emptyTitle'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text),
          ),
        ],
      ),
    );
  }
}

/// Một dòng báo trong nhóm: biểu tượng mức độ, biển xe, trạng thái, mô tả 2 dòng, giờ gửi
class _ReportRow extends StatelessWidget {
  final BreakdownReport report;
  final VoidCallback onTap;

  const _ReportRow({required this.report, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final List<String> meta = <String>[
      momentText(report.reportedAt),
      if (report.orderCode.isNotEmpty) report.orderCode,
      if (report.photoUrls.isNotEmpty) t('breakdowns.photoCount', {'count': report.photoUrls.length}),
    ];
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        highlightColor: IosColors.fill,
        splashFactory: NoSplash.splashFactory,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              IosIconBadge(icon: severityIcon(report.severity), color: severityColor(report.severity)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            report.vehicleLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IosPill(
                          tEnum('breakdownStatus', report.status),
                          color: _statusColor(report.status),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      report.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, color: AppColors.text, height: 1.3),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      meta.join(' · '),
                      style: const TextStyle(fontSize: 13, color: IosColors.secondaryLabel),
                    ),
                    if (report.resolutionNote.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        report.resolutionNote,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: AppColors.okText),
                      ),
                    ],
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 4, top: 6),
                child: Icon(CupertinoIcons.chevron_forward, size: 18, color: IosColors.tertiaryLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bảng kéo lên kiểu iOS xem chi tiết một báo của mình
Future<void> showBreakdownSheet(BuildContext context, BreakdownReport report) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.25),
    builder: (BuildContext context) => _BreakdownSheet(report: report),
  );
}

class _BreakdownSheet extends StatelessWidget {
  final BreakdownReport report;

  const _BreakdownSheet({required this.report});

  @override
  Widget build(BuildContext context) {
    final Color tint = severityColor(report.severity);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (BuildContext context, ScrollController controller) {
        return Glass(
          opacity: 0.86,
          blur: 30,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
          child: ListView(
            controller: controller,
            padding: EdgeInsets.zero,
            children: <Widget>[
              const SheetGrabber(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 16),
                child: Row(
                  children: <Widget>[
                    IosIconBadge(icon: severityIcon(report.severity), color: tint, size: 44),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            report.vehicleLabel,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text, letterSpacing: -0.3),
                          ),
                          Text(
                            tEnum('breakdownSeverity', report.severity),
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: tint),
                          ),
                        ],
                      ),
                    ),
                    GlassCircleButton(
                      icon: Icons.close_rounded,
                      tooltip: t('common.close'),
                      size: 36,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              IosGroup(
                header: t('breakdowns.progress'),
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    child: _ProgressSteps(report: report),
                  ),
                ],
              ),
              IosGroup(
                header: t('breakdowns.description'),
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(report.description, style: const TextStyle(fontSize: 16, height: 1.4, color: AppColors.text)),
                  ),
                ],
              ),
              if (report.photoUrls.isNotEmpty)
                IosGroup(
                  header: t('breakdowns.photos', {'count': report.photoUrls.length}),
                  children: <Widget>[
                    SizedBox(
                      height: 112,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.all(12),
                        itemCount: report.photoUrls.length,
                        separatorBuilder: (BuildContext _, int __) => const SizedBox(width: 10),
                        itemBuilder: (BuildContext context, int index) {
                          return GestureDetector(
                            onTap: () => _openPhoto(context, report.photoUrls[index]),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                report.photoUrls[index],
                                width: 88,
                                height: 88,
                                fit: BoxFit.cover,
                                errorBuilder: (BuildContext _, Object __, StackTrace? ___) => Container(
                                  width: 88,
                                  height: 88,
                                  color: IosColors.fill,
                                  child: const Icon(Icons.broken_image_outlined, color: IosColors.secondaryLabel),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              if (report.resolutionNote.isNotEmpty)
                IosGroup(
                  header: t('breakdowns.resolutionNote'),
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        report.resolutionNote,
                        style: const TextStyle(fontSize: 16, height: 1.4, color: AppColors.okText),
                      ),
                    ),
                  ],
                ),
              IosGroup(
                children: <Widget>[
                  _InfoRow(label: t('breakdowns.sentAt'), value: momentText(report.reportedAt)),
                  if (report.orderCode.isNotEmpty) _InfoRow(label: t('breakdowns.trip'), value: report.orderCode),
                ],
              ),
              if (report.severity == 'MustStop' && report.status != 'Resolved')
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
                  child: Text(
                    t('breakdowns.mustStopNotice'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: IosColors.secondaryLabel, height: 1.4),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _openPhoto(BuildContext context, String url) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: Center(child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain))),
      ),
    ));
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: <Widget>[
          Text(label, style: const TextStyle(fontSize: 16, color: AppColors.text)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 16, color: IosColors.secondaryLabel)),
        ],
      ),
    );
  }
}

/// Ba chấm nối nhau: Đã gửi → Điều phối đã nhận → Đã xử lý, kèm giờ và người làm
class _ProgressSteps extends StatelessWidget {
  final BreakdownReport report;

  const _ProgressSteps({required this.report});

  @override
  Widget build(BuildContext context) {
    final int current = report.progressStep;
    final List<({String title, String detail})> steps = <({String title, String detail})>[
      (title: tEnum('breakdownStatus', 'Open'), detail: momentText(report.reportedAt)),
      (
        title: tEnum('breakdownStatus', 'Acknowledged'),
        detail: report.acknowledgedAt.isEmpty
            ? t('breakdowns.waiting')
            : '${momentText(report.acknowledgedAt)}${report.acknowledgedByName.isEmpty ? '' : ' · ${report.acknowledgedByName}'}',
      ),
      (
        title: tEnum('breakdownStatus', 'Resolved'),
        detail: report.resolvedAt.isEmpty
            ? t('breakdowns.notYet')
            : '${momentText(report.resolvedAt)}${report.resolvedByName.isEmpty ? '' : ' · ${report.resolvedByName}'}',
      ),
    ];
    final List<Widget> rows = <Widget>[];
    for (int index = 0; index < steps.length; index++) {
      final bool done = index <= current;
      final bool last = index == steps.length - 1;
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              width: 24,
              child: Column(
                children: <Widget>[
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done ? IosColors.green : Colors.white,
                      border: done ? null : Border.all(color: const Color(0xFFC7C7CC), width: 2),
                    ),
                    child: done ? const Icon(Icons.check_rounded, size: 15, color: Colors.white) : null,
                  ),
                  if (!last)
                    Expanded(
                      child: Container(
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        color: index < current ? IosColors.green : const Color(0xFFE5E5EA),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: last ? 0 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      steps[index].title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: index == current ? FontWeight.w600 : FontWeight.w400,
                        color: done ? AppColors.text : IosColors.secondaryLabel,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(steps[index].detail, style: const TextStyle(fontSize: 13, color: IosColors.secondaryLabel)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ));
    }
    return Column(children: rows);
  }
}

/// "Hôm nay 09:12" nếu trong ngày, còn lại "12/10 09:12"
String momentText(String isoText) {
  if (isoText.isEmpty) {
    return '';
  }
  final DateTime moment = DateTime.parse(isoText).toLocal();
  final DateTime now = DateTime.now();
  final String time = '${moment.hour.toString().padLeft(2, '0')}:${moment.minute.toString().padLeft(2, '0')}';
  if (moment.year == now.year && moment.month == now.month && moment.day == now.day) {
    return t('common.todayAt', {'time': time});
  }
  return '${moment.day.toString().padLeft(2, '0')}/${moment.month.toString().padLeft(2, '0')} $time';
}
