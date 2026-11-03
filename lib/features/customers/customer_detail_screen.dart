// C2: chi tiết khách: gọi, email, số đơn, thông tin, đơn gần đây (theo màn N4-ChiTietKhach).
// Sửa thông tin khách làm trên web. "Đơn gần đây" ẩn khi không có Orders.View.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// Riverpod: ConsumerWidget, WidgetRef, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/ios.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/page_transition.dart';
import '../fleet/shared.dart';
import '../roles/role_detail_screen.dart';
import 'customers_api.dart';

class CustomerDetailScreen extends ConsumerWidget {
  final String customerId;

  const CustomerDetailScreen({super.key, required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<CustomerDetail> detailValue = ref.watch(customerProvider(customerId));
    final bool canViewOrders = userCan(ref, 'Orders.View');
    String title = t('customers.title');
    if (detailValue.value != null) {
      title = detailValue.value!.customer.customerName;
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: AsyncView<CustomerDetail>(
        value: detailValue,
        onRetry: () {
          ref.invalidate(customerProvider(customerId));
        },
        builder: (CustomerDetail detail) {
          final Customer customer = detail.customer;
          final bool hasEmail = customer.email != null && customer.email!.isNotEmpty;
          return RefreshIndicator(
            onRefresh: () {
              ref.invalidate(customerOrdersProvider(customerId));
              return ref.refresh(customerProvider(customerId).future);
            },
            child: ListView(
              padding: withTabBarInset(context, const EdgeInsets.fromLTRB(16, 12, 16, 32)),
              children: [
                Row(
                  children: [
                    if (customer.phone.isNotEmpty)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            callPhone(context, customer.phone);
                          },
                          icon: const Icon(Icons.call_outlined, size: 18),
                          label: Text(t('common.call')),
                        ),
                      ),
                    if (customer.phone.isNotEmpty && hasEmail) const SizedBox(width: 8),
                    if (hasEmail)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            openUri(context, Uri(scheme: 'mailto', path: customer.email));
                          },
                          icon: const Icon(Icons.mail_outline, size: 18),
                          label: const Text('Email'),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                WhiteBox(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: StatTile('${detail.totalOrdersCount}', t('customers.totalOrders'))),
                      Expanded(child: StatTile('${detail.activeOrdersCount}', t('customers.activeOrders'))),
                      // Server trả null thì ẩn ô "Đã chi"
                      if (detail.totalSpentAmount != null)
                        Expanded(flex: 2, child: StatTile(formatMoney(detail.totalSpentAmount), t('customers.spent'))),
                    ],
                  ),
                ),
                DetailSectionTitle(t('customers.info')),
                WhiteBox(
                  child: Column(
                    children: [
                      // Ô nào null thì ẩn dòng đó
                      InfoRow(t('customers.code'), customer.customerCode),
                      if (customer.contactPerson != null) InfoRow(t('customers.contact'), customer.contactPerson!),
                      if (customer.phone.isNotEmpty) InfoRow(t('customers.phone'), customer.phone),
                      if (hasEmail) InfoRow('Email', customer.email!),
                      if (customer.taxCode != null) InfoRow(t('customers.taxCode'), customer.taxCode!),
                      if (customer.address != null) InfoRow(t('customers.address'), customer.address!),
                      if (detail.note != null) InfoRow(t('customers.note'), detail.note!),
                    ],
                  ),
                ),
                if (canViewOrders) ...[
                  DetailSectionTitle(t('customers.recentOrders')),
                  RecentOrdersBox(customerId: customerId),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

// Màu nhãn trạng thái đơn
/// Màu theo bước của đơn, dùng các màu hệ thống bản tương phản cao của iOS để chữ đọc rõ trên nền nhạt.
/// Màu lạ (trạng thái mới từ server) về xám.
Color orderStatusColor(String status) {
  Color pick(int light, int dark) => Color(AppColors.isDark ? dark : light);
  return switch (status) {
    'Quoted' => pick(0xFF0062CC, 0xFF409CFF), // xanh dương
    'CustomerConfirmed' => pick(0xFF0071A4, 0xFF70D7FF), // xanh trời
    'Scheduled' => pick(0xFF3634A3, 0xFF7D7AFF), // chàm
    'InProgress' => pick(0xFFC93400, 0xFFFFB340), // cam
    'AwaitingFinalization' => pick(0xFF8944AB, 0xFFDA8FFF), // tím
    'Finalized' => pick(0xFF248A3D, 0xFF30DB5B), // xanh lá
    'Invoiced' => pick(0xFF00817A, 0xFF66D4CF), // bạc hà
    'Cancelled' => pick(0xFFD70015, 0xFFFF6961), // đỏ
    _ => pick(0xFF6C6C70, 0xFF98989D), // Draft: xám
  };
}

Widget orderStatusPill(String status) => IosPill(tEnum('orderStatus', status), color: orderStatusColor(status));

class RecentOrdersBox extends ConsumerWidget {
  final String customerId;

  const RecentOrdersBox({super.key, required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<RecentOrder>> ordersValue = ref.watch(customerOrdersProvider(customerId));
    Widget body;
    if (ordersValue.hasError && !ordersValue.isLoading) {
      body = Row(
        children: [
          Expanded(child: Text(errorMessage(ordersValue.error!), style: TextStyle(color: AppColors.errorText))),
          TextButton(
            onPressed: () {
              ref.invalidate(customerOrdersProvider(customerId));
            },
            child: Text(t('common.retry')),
          ),
        ],
      );
    } else if (!ordersValue.hasValue) {
      body = const Center(child: CupertinoActivityIndicator(radius: 14));
    } else if (ordersValue.value!.isEmpty) {
      body = Text(t('customers.noOrders'), style: TextStyle(color: AppColors.textMuted));
    } else {
      final List<Widget> rows = <Widget>[];
      for (final RecentOrder order in ordersValue.value!) {
        rows.add(InkWell(
          // Mở chi tiết đơn của người 2
          onTap: () {
            context.push('/orders/${order.publicId}');
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${order.orderCode} · ${formatDay(order.scheduledDate ?? order.createdAt)}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                orderStatusPill(order.status),
              ],
            ),
          ),
        ));
      }
      body = Column(children: rows);
    }
    return WhiteBox(child: body);
  }
}
