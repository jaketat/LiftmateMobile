// M4: danh sách xe sắp hoặc đã đến hạn bảo trì theo định mức của từng xe.
// Câu mô tả dùng nguyên văn message của server nên không tự tính lại ở app.
import 'package:flutter/cupertino.dart';
// Riverpod: ConsumerWidget, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ios.dart';
import '../auth/session_provider.dart';
import 'maintenance_api.dart';
import 'maintenance_plan_screen.dart';
import 'maintenance_providers.dart';

class DueAlertsScreen extends ConsumerStatefulWidget {
  const DueAlertsScreen({super.key});

  @override
  ConsumerState<DueAlertsScreen> createState() => _DueAlertsScreenState();
}

class _DueAlertsScreenState extends ConsumerState<DueAlertsScreen> {
  // Xe đang mở ô sửa định mức. Bấm thẻ xe nào thì mở định mức của xe đó ngay bên dưới.
  MaintenanceDueAlert? selected;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<MaintenanceDueAlert>> alertsValue = ref.watch(dueAlertsProvider);
    final List<MaintenanceDueAlert>? alerts = alertsValue.value;
    final Session? session = ref.watch(sessionProvider).value;
    // Người không có quyền sửa thì không thấy nút lập lịch, chỉ xem
    final bool canSchedule = session != null && session.can('Vehicles.Maintenance');
    final MaintenanceDueAlert? chosen = selected;

    return IosPage(
      title: t('maintenance.dueAlerts.title'),
      onRefresh: () => ref.refresh(dueAlertsProvider.future),
      slivers: <Widget>[
        if (alerts == null)
          SliverFillRemaining(
            hasScrollBody: false,
            child: AsyncView<List<MaintenanceDueAlert>>(
              value: alertsValue,
              onRetry: () => ref.invalidate(dueAlertsProvider),
              builder: (List<MaintenanceDueAlert> _) => const SizedBox.shrink(),
            ),
          )
        else if (alerts.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: IosCenterMessage(text: t('maintenance.dueAlerts.empty'), icon: CupertinoIcons.checkmark_seal),
          )
        else ...<Widget>[
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.list(
              children: <Widget>[
                for (final MaintenanceDueAlert alert in alerts)
                  DueAlertCard(
                    alert: alert,
                    canSchedule: canSchedule,
                    isOpen: chosen?.vehiclePublicId == alert.vehiclePublicId,
                    onTap: () {
                      // Bấm lại chính xe đang mở thì đóng lại
                      setState(() {
                        selected = selected?.vehiclePublicId == alert.vehiclePublicId ? null : alert;
                      });
                    },
                  ),
              ],
            ),
          ),
          // Ô sửa định mức của xe vừa bấm, nằm ngay dưới danh sách
          if (chosen != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: MaintenancePlanEditor(vehicleId: chosen.vehiclePublicId, vehicleLabel: chosen.vehicleLabel),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 4, 32, 24),
              child: Text(
                t('maintenance.dueAlerts.note'),
                style: TextStyle(fontSize: 13, height: 1.35, color: IosColors.secondaryLabel),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Thẻ một xe: biển số, mức độ, câu của server, và hoặc nút lập lịch hoặc ngày đã lên lịch.
/// Bấm thẻ thì mở ô sửa định mức của chính xe này, ngay bên dưới danh sách.
class DueAlertCard extends StatelessWidget {
  final MaintenanceDueAlert alert;
  final bool canSchedule;
  final bool isOpen;
  final VoidCallback onTap;

  const DueAlertCard({
    super.key,
    required this.alert,
    required this.canSchedule,
    required this.onTap,
    this.isOpen = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool isOverdue = alert.isOverdue;
    return IosCard(
      onTap: onTap,
      borderColor: isOverdue ? IosColors.red.withValues(alpha: 0.45) : (isOpen ? AppColors.navy.withValues(alpha: 0.4) : null),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          IosIconBadge(icon: CupertinoIcons.car_detailed, color: isOverdue ? IosColors.red : IosColors.orange, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        alert.vehicleLabel,
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: isOverdue ? AppColors.errorText : AppColors.text),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IosPill(
                      isOverdue ? t('maintenance.dueAlerts.overdue') : t('maintenance.dueAlerts.upcoming'),
                      color: isOverdue ? IosColors.red : IosColors.orange,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(alert.message, style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.textMuted)),
                const SizedBox(height: 8),
                // Đã có lịch sắp tới thì chỉ báo ngày, không mời lập thêm
                if (alert.upcomingScheduledStart.isNotEmpty)
                  Row(
                    children: <Widget>[
                      Icon(CupertinoIcons.calendar_badge_plus, size: 17, color: AppColors.navy),
                      const SizedBox(width: 6),
                      Text(
                        t('maintenance.dueAlerts.scheduledOn', <String, Object?>{'date': formatDate(alert.upcomingScheduledStart)}),
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.navy),
                      ),
                    ],
                  )
                else if (canSchedule)
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(44, 32),
                    onPressed: () => context.push('/maintenance/new?vehicleId=${alert.vehiclePublicId}'),
                    child: Text(
                      t('maintenance.dueAlerts.schedule'),
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: IosColors.blue),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
