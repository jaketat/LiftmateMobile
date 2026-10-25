// C1: danh sách khách hàng, tìm theo chữ, cuộn tải thêm, nút "Thêm khách" (theo màn N4-KhachHang)
import 'package:flutter/material.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../fleet/shared.dart';
import 'customers_api.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() {
    return _CustomersScreenState();
  }
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  String search = '';
  // Tăng lên để danh sách tải lại (sau khi thêm khách)
  int reloadCount = 0;

  @override
  Widget build(BuildContext context) {
    Widget? addButton;
    if (userCan(ref, 'Customers.Create')) {
      addButton = FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/customers/new');
          setState(() {
            reloadCount = reloadCount + 1;
          });
        },
        icon: const Icon(Icons.add),
        label: const Text('Thêm khách'),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Khách hàng')),
      floatingActionButton: addButton,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchField(
              hint: 'Tìm tên, mã, SĐT, mã số thuế…',
              onChanged: (String text) {
                setState(() {
                  search = text;
                });
              },
            ),
          ),
          Expanded(
            child: PagedList<Customer>(
              key: ValueKey<String>('$search|$reloadCount'),
              fetchPage: (int pageNumber) {
                return fetchCustomers(pageNumber, search);
              },
              emptyText: 'Không có khách nào.',
              itemBuilder: (Customer customer) {
                return CustomerCard(customer: customer);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class CustomerCard extends StatelessWidget {
  final Customer customer;

  const CustomerCard({super.key, required this.customer});

  @override
  Widget build(BuildContext context) {
    final List<String> parts = <String>[customer.customerCode];
    if (customer.isWalkIn) {
      parts.add('khách vãng lai');
    } else if (customer.contactPerson != null && customer.contactPerson!.isNotEmpty) {
      parts.add(customer.contactPerson!);
    }
    if (customer.phone.isNotEmpty) {
      parts.add(customer.phone);
    }
    return TapCard(
      onTap: () {
        context.push('/customers/${customer.publicId}');
      },
      child: Row(
        children: [
          InitialsAvatar(customer.customerName, isMuted: customer.isWalkIn),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(customer.customerName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                Text(parts.join(' · '), style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textMuted),
        ],
      ),
    );
  }
}
