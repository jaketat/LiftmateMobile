// B3: cảnh báo giấy tờ xe và người, lọc theo mức (theo màn N4-CanhBao).
// Viền đỏ = giấy chặn xe chạy (blocksCapability khác null), không viền = chỉ nhắc.
// Tab Xe cần Reports.ViewOperations, tab Nhân sự cần Users.ManageComplianceDocs.
import 'package:flutter/material.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/page_transition.dart';
import '../fleet/shared.dart';
import '../staff/staff_api.dart';
import 'dashboard_api.dart';

Map<String?, String> get urgencyOptions => <String?, String>{
  null: t('alerts.urgency.all'),
  'Expired': t('alerts.urgency.expired'),
  'Urgent': t('alerts.urgency.urgent'),
  'Reminder': t('alerts.urgency.reminder'),
};

class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() {
    return _AlertsScreenState();
  }
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  String? urgency;

  @override
  Widget build(BuildContext context) {
    final bool canVehicles = userCan(ref, 'Reports.ViewOperations');
    final bool canStaff = userCan(ref, 'Users.ManageComplianceDocs');

    final List<Tab> tabs = <Tab>[];
    final List<Widget> pages = <Widget>[];
    if (canVehicles) {
      final int? total = ref.watch(vehicleAlertsProvider(null)).value?.length;
      tabs.add(Tab(text: total == null ? t('alerts.tabVehicles') : t('alerts.tabVehiclesCount', <String, Object?>{'count': total})));
      pages.add(vehicleList());
    }
    if (canStaff) {
      final int? total = ref.watch(staffAlertsProvider(null)).value?.length;
      tabs.add(Tab(text: total == null ? t('alerts.tabStaff') : t('alerts.tabStaffCount', <String, Object?>{'count': total})));
      pages.add(staffList());
    }

    if (tabs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(t('alerts.title'))),
        body: EmptyView(text: t('alerts.noAccess')),
      );
    }

    // DefaultTabController (Flutter): giữ tab đang chọn cho TabBar và TabBarView
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(title: Text(t('alerts.title')), bottom: TabBar(tabs: tabs)),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: FilterChips(
                options: urgencyOptions,
                selected: urgency,
                onSelected: (String? value) {
                  setState(() {
                    urgency = value;
                  });
                },
              ),
            ),
            Expanded(child: TabBarView(children: pages)),
          ],
        ),
      ),
    );
  }

  Widget vehicleList() {
    return AsyncView<List<VehicleAlert>>(
      value: ref.watch(vehicleAlertsProvider(urgency)),
      onRetry: () {
        ref.invalidate(vehicleAlertsProvider(urgency));
      },
      isEmpty: (List<VehicleAlert> alerts) {
        return alerts.isEmpty;
      },
      emptyText: t('alerts.vehiclesEmpty'),
      builder: (List<VehicleAlert> alerts) {
        return RefreshIndicator(
          onRefresh: () {
            return ref.refresh(vehicleAlertsProvider(urgency).future);
          },
          child: ListView.builder(
            padding: withTabBarInset(context, const EdgeInsets.fromLTRB(16, 0, 16, 24)),
            itemCount: alerts.length,
            itemBuilder: (BuildContext context, int index) {
              return VehicleAlertCard(alert: alerts[index]);
            },
          ),
        );
      },
    );
  }

  Widget staffList() {
    return AsyncView<List<StaffAlert>>(
      value: ref.watch(staffAlertsProvider(urgency)),
      onRetry: () {
        ref.invalidate(staffAlertsProvider(urgency));
      },
      isEmpty: (List<StaffAlert> alerts) {
        return alerts.isEmpty;
      },
      emptyText: t('alerts.staffEmpty'),
      builder: (List<StaffAlert> alerts) {
        return RefreshIndicator(
          onRefresh: () {
            return ref.refresh(staffAlertsProvider(urgency).future);
          },
          child: ListView.builder(
            padding: withTabBarInset(context, const EdgeInsets.fromLTRB(16, 0, 16, 24)),
            itemCount: alerts.length,
            itemBuilder: (BuildContext context, int index) {
              final StaffAlert alert = alerts[index];
              return TapCard(
                onTap: () {
                  context.push('/staff/${alert.userPublicId}');
                },
                child: alertBody(
                  alert.fullName,
                  alert.daysRemaining,
                  t('alerts.docLine', <String, Object?>{
                    'document': label(personDocumentLabels, alert.documentType),
                    'date': formatDay(alert.effectiveUntil),
                  }),
                  Text(t('alerts.staffNote'), style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// Phần chữ của một thẻ cảnh báo: tên + nhãn hạn, loại giấy · ngày hết, câu giải thích
Widget alertBody(String title, int daysRemaining, String docLine, Widget note) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
          daysPill(daysRemaining),
        ],
      ),
      const SizedBox(height: 4),
      Text(docLine, style: const TextStyle(fontSize: 14)),
      const SizedBox(height: 2),
      note,
    ],
  );
}

class VehicleAlertCard extends StatelessWidget {
  final VehicleAlert alert;

  const VehicleAlertCard({super.key, required this.alert});

  @override
  Widget build(BuildContext context) {
    final bool blocks = alert.blocksCapability != null;
    Widget note = Text(t('alerts.vehicleNote'), style: TextStyle(fontSize: 13, color: AppColors.textMuted));
    if (blocks) {
      note = Text(
        alert.daysRemaining < 0 ? t('alerts.vehicleBlockedNow') : t('alerts.vehicleWillBlock'),
        style: TextStyle(fontSize: 13, color: AppColors.errorText, fontWeight: FontWeight.w600),
      );
    }
    return TapCard(
      borderColor: blocks ? AppColors.errorText : AppColors.border,
      borderWidth: blocks ? 2 : 1,
      // Mở chi tiết xe để gia hạn
      onTap: () {
        context.push('/fleet/${alert.vehiclePublicId}');
      },
      child: alertBody(
        alert.plateNumber,
        alert.daysRemaining,
        t('alerts.docLine', <String, Object?>{
          'document': label(vehicleDocumentLabels, alert.documentType),
          'date': formatDay(alert.effectiveUntil),
        }),
        note,
      ),
    );
  }
}
