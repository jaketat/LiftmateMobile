// M4: danh sách xe sắp hoặc đã đến hạn bảo trì theo định mức của từng xe.
// Câu mô tả dùng nguyên văn message của server nên không tự tính lại ở app.
import 'package:flutter/material.dart';
// Riverpod: ConsumerWidget, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../auth/session_provider.dart';
import 'maintenance_api.dart';
import 'maintenance_plan_screen.dart';
import 'maintenance_providers.dart';
import 'widgets.dart';

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
    final Session? session = ref.watch(sessionProvider).value;
    // Người không có quyền sửa thì không thấy nút lập lịch, chỉ xem
    final bool canSchedule = session != null && session.can('Vehicles.Maintenance');

    return Scaffold(
      appBar: AppBar(title: const Text('Đền hạn bảo trì')),
      body: AsyncView<List<MaintenanceDueAlert>>(
        value: alertsValue,
        onRetry: () {
          ref.invalidate(dueAlertsProvider);
        },
        isEmpty: (List<MaintenanceDueAlert> alerts) {
          return alerts.isEmpty;
        },
        emptyText: 'Chưa có xe nào sắp hoặc đã đến hạn bảo trì.',
        builder: (List<MaintenanceDueAlert> alerts) {
          final List<Widget> children = <Widget>[];
          for (final MaintenanceDueAlert alert in alerts) {
            children.add(
              DueAlertCard(
                alert: alert,
                canSchedule: canSchedule,
                onTap: () {
                  // Bấm lại chính xe đang mở thì đóng lại
                  setState(() {
                    selected = selected?.vehiclePublicId == alert.vehiclePublicId ? null : alert;
                  });
                },
              ),
            );
          }

          // Ô sửa định mức của xe vừa bấm, nằm ngay dưới danh sách
          final MaintenanceDueAlert? chosen = selected;
          if (chosen != null) {
            children.add(
              MaintenancePlanEditor(
                vehicleId: chosen.vehiclePublicId,
                vehicleLabel: chosen.vehicleLabel,
              ),
            );
          }

          children.add(
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 6, 20, 24),
              child: NoteText(
                'Quá hạn lên trước. Câu mô tả tờ tay từ message của server. '
                'Bấm một xe để sửa định mức bên dưới.',
              ),
            ),
          );
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            children: children,
          );
        },
      ),
    );
  }
}

/// Thẻ một xe: biển số, mức độ, câu của server, và hoặc nút lập lịch hoặc ngày đã lên lịch.
class DueAlertCard extends StatelessWidget {
  final MaintenanceDueAlert alert;
  final bool canSchedule;
  final VoidCallback onTap;

  const DueAlertCard({
    super.key,
    required this.alert,
    required this.canSchedule,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isOverdue = alert.isOverdue;

    final List<Widget> children = <Widget>[
      Row(
        children: <Widget>[
          Expanded(
            child: Text(
              alert.vehicleLabel,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isOverdue ? AppColors.errorText : AppColors.text,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ToneChip(
            isOverdue ? 'Quá hạn' : 'Sắp đến',
            tone: isOverdue ? Tone.danger : Tone.warn,
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        alert.message,
        style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.textMuted),
      ),
      const SizedBox(height: 10),
    ];

    if (alert.upcomingScheduledStart.isNotEmpty) {
      // Đã có lịch sắp tới thì chỉ báo ngày, không mời lập thêm
      children.add(
        Row(
          children: <Widget>[
            const Icon(Icons.event_available_outlined, size: 17, color: AppColors.navy),
            const SizedBox(width: 8),
            Text(
              'Đã lên lịch ngày ${formatDate(alert.upcomingScheduledStart)}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.navy),
            ),
          ],
        ),
      );
    } else if (canSchedule) {
      children.add(
        InkWell(
          onTap: () {
            context.push('/maintenance/new?vehicleId=${alert.vehiclePublicId}');
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Lập lịch định kỳ',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.navy,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.navy,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isOverdue ? AppColors.errorBackground : Colors.white,
        border: Border.all(color: isOverdue ? const Color(0xFFF3B5AE) : AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      // Bấm thẻ thì mở ô sửa định mức của chính xe này, ngay bên dưới danh sách
      child: Material(
        // Material trong suốt để InkWell vẽ được gợn sóng ngay trên thẻ
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      ),
    );
  }
}