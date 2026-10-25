// C2: chi tiết khách: gọi, email, số đơn, thông tin, đơn gần đây (theo màn N4-ChiTietKhach).
// Sửa thông tin khách làm trên web. "Đơn gần đây" ẩn khi không có Orders.View.
import 'package:flutter/material.dart';
// Riverpod: ConsumerWidget, WidgetRef, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
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
    String title = 'Khách hàng';
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
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
                          label: const Text('Gọi'),
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
                      Expanded(child: StatTile('${detail.totalOrdersCount}', 'Tổng đơn')),
                      Expanded(child: StatTile('${detail.activeOrdersCount}', 'Đang chạy')),
                      // Server trả null thì ẩn ô "Đã chi"
                      if (detail.totalSpentAmount != null)
                        Expanded(flex: 2, child: StatTile(formatMoney(detail.totalSpentAmount), 'Đã chi')),
                    ],
                  ),
                ),
                const DetailSectionTitle('Thông tin'),
                WhiteBox(
                  child: Column(
                    children: [
                      // Ô nào null thì ẩn dòng đó
                      InfoRow('Mã khách', customer.customerCode),
                      if (customer.contactPerson != null) InfoRow('Người liên hệ', customer.contactPerson!),
                      if (customer.phone.isNotEmpty) InfoRow('Số điện thoại', customer.phone),
                      if (hasEmail) InfoRow('Email', customer.email!),
                      if (customer.taxCode != null) InfoRow('Mã số thuế', customer.taxCode!),
                      if (customer.address != null) InfoRow('Địa chỉ', customer.address!),
                      if (detail.note != null) InfoRow('Ghi chú', detail.note!),
                    ],
                  ),
                ),
                if (canViewOrders) ...[
                  const DetailSectionTitle('Đơn gần đây'),
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
Pill orderStatusPill(String status) {
  final String text = label(orderStatusLabels, status);
  switch (status) {
    case 'Finalized':
      return Pill.ok(text);
    case 'Invoiced':
      return Pill.gray(text);
    case 'Cancelled':
      return Pill.error(text);
    default:
      return Pill.navy(text);
  }
}

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
          Expanded(child: Text(errorMessage(ordersValue.error!), style: const TextStyle(color: AppColors.errorText))),
          TextButton(
            onPressed: () {
              ref.invalidate(customerOrdersProvider(customerId));
            },
            child: const Text('Thử lại'),
          ),
        ],
      );
    } else if (!ordersValue.hasValue) {
      body = const Center(child: CircularProgressIndicator());
    } else if (ordersValue.value!.isEmpty) {
      body = const Text('Khách chưa có đơn nào.', style: TextStyle(color: AppColors.textMuted));
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
