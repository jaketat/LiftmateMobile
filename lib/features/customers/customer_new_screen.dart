// C3: thêm khách. Tên và SĐT bắt buộc, mã khách server tự sinh (theo màn N4-ThemKhach).
// Lưu xong mở chi tiết khách vừa tạo. Lỗi từng ô (VALIDATION_FAILED) hiện dưới ô tương ứng.
import 'package:flutter/material.dart';
// go_router: context.pushReplacement
import 'package:go_router/go_router.dart';

import '../../core/api/call.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../fleet/shared.dart';
import 'customers_api.dart';

class CustomerNewScreen extends StatefulWidget {
  const CustomerNewScreen({super.key});

  @override
  State<CustomerNewScreen> createState() {
    return _CustomerNewScreenState();
  }
}

class _CustomerNewScreenState extends State<CustomerNewScreen> {
  // Tên trường gửi server → ô nhập
  final Map<String, TextEditingController> controllers = <String, TextEditingController>{
    'customerName': TextEditingController(),
    'phone': TextEditingController(),
    'contactPerson': TextEditingController(),
    'email': TextEditingController(),
    'taxCode': TextEditingController(),
    'address': TextEditingController(),
  };
  bool isSaving = false;
  String? errorText;
  Map<String, String> fieldErrors = <String, String>{};

  @override
  void dispose() {
    for (final TextEditingController controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String textOf(String field) {
    return controllers[field]!.text.trim();
  }

  Future<void> save() async {
    // Hai ô bắt buộc: báo ngay, đỡ gọi server
    final Map<String, String> missing = <String, String>{};
    if (textOf('customerName').isEmpty) {
      missing['customerName'] = 'Nhập tên khách hàng.';
    }
    if (textOf('phone').isEmpty) {
      missing['phone'] = 'Nhập số điện thoại.';
    }
    if (missing.isNotEmpty) {
      setState(() {
        fieldErrors = missing;
        errorText = null;
      });
      return;
    }

    setState(() {
      isSaving = true;
      errorText = null;
      fieldErrors = <String, String>{};
    });
    // Ô bỏ trống thì gửi null
    final Map<String, dynamic> body = <String, dynamic>{};
    for (final String field in controllers.keys) {
      body[field] = textOf(field).isEmpty ? null : textOf(field);
    }
    try {
      final CustomerDetail created = await createCustomer(body);
      if (!mounted) {
        return;
      }
      context.pushReplacement('/customers/${created.customer.publicId}');
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        isSaving = false;
        errorText = errorMessage(error);
        if (error is ApiException) {
          fieldErrors = error.fieldErrors;
        }
      });
    }
  }

  Widget field(String name, String labelText, {TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controllers[name],
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: labelText, errorText: fieldError(fieldErrors, name)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Thêm khách hàng')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          field('customerName', 'Tên khách hàng *'),
          field('phone', 'Số điện thoại *', keyboard: TextInputType.phone),
          field('contactPerson', 'Người liên hệ'),
          field('email', 'Email', keyboard: TextInputType.emailAddress),
          field('taxCode', 'Mã số thuế'),
          field('address', 'Địa chỉ'),
          const Text(
            'Mã khách (KH-0012…) do server tự sinh.',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          if (errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(errorText!, style: const TextStyle(color: AppColors.errorText)),
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: isSaving ? null : save,
            child: Text(isSaving ? 'Đang lưu…' : 'Lưu khách hàng'),
          ),
        ],
      ),
    );
  }
}
