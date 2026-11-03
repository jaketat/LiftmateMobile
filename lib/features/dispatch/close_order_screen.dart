// K11: chốt đơn và hóa đơn, 3 bước (theo màn N3-ChotDon trên canvas)
import 'package:flutter/material.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/call.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/page_transition.dart';
import '../auth/session_provider.dart';
import 'close_order_api.dart';

// Trạng thái đơn theo thứ tự, để biết bước nào xong, bước nào đang làm
const List<String> _afterFinish = <String>['AwaitingFinalization', 'Finalized', 'Invoiced'];
const List<String> _afterFinalize = <String>['Finalized', 'Invoiced'];

class CloseOrderScreen extends ConsumerStatefulWidget {
  final String orderId;

  const CloseOrderScreen({super.key, required this.orderId});

  @override
  ConsumerState<CloseOrderScreen> createState() => _CloseOrderScreenState();
}

class _CloseOrderScreenState extends ConsumerState<CloseOrderScreen> {
  final TextEditingController _invoiceController = TextEditingController();
  // true: đang gọi API, khóa mọi nút
  bool _busy = false;
  // Lỗi hiện dưới ô số hóa đơn
  String _invoiceError = '';

  @override
  void dispose() {
    _invoiceController.dispose();
    super.dispose();
  }

  // Chạy một thao tác ghi: khóa nút, báo lỗi nếu có, rồi luôn tải lại đơn từ server
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _invoiceError = '';
    });
    try {
      await action();
    } on ApiException catch (error) {
      if (mounted) {
        if (error.code == 'INVOICE_NUMBER_REQUIRED') {
          setState(() {
            _invoiceError = error.message;
          });
        } else {
          showErrorSnackBar(context, error);
        }
      }
    } catch (error) {
      if (mounted) {
        showErrorSnackBar(context, error);
      }
    }
    ref.invalidate(closeOrderProvider(widget.orderId));
    if (mounted) {
      setState(() {
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<CloseOrder> orderValue = ref.watch(closeOrderProvider(widget.orderId));
    final Session? session = ref.watch(sessionProvider).value;
    bool can(String permission) {
      return session != null && session.can(permission);
    }

    String subtitle = '';
    final CloseOrder? loaded = orderValue.value;
    if (loaded != null) {
      final List<String> parts = <String>[];
      if (loaded.orderCode.isNotEmpty) {
        parts.add(loaded.orderCode);
      }
      if (loaded.customerName.isNotEmpty) {
        parts.add(loaded.customerName);
      }
      subtitle = parts.join(' · ');
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('dispatch.close.title'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            if (subtitle.isNotEmpty)
              Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
      ),
      body: AsyncView<CloseOrder>(
        value: orderValue,
        onRetry: () {
          ref.invalidate(closeOrderProvider(widget.orderId));
        },
        builder: (CloseOrder order) {
          return RefreshIndicator(
            onRefresh: () {
              return ref.refresh(closeOrderProvider(widget.orderId).future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: withTabBarInset(context, const EdgeInsets.all(16)),
              children: [
                _buildStep1(order, can('Orders.Dispatch')),
                const SizedBox(height: 12),
                _buildStep2(order, can('Orders.Edit'), can('Orders.ApproveCost')),
                const SizedBox(height: 12),
                _buildStep3(order, can('Orders.Invoice')),
                const SizedBox(height: 12),
                Text(
                  t('dispatch.close.footer'),
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Bước 1: xong việc tại hiện trường
  Widget _buildStep1(CloseOrder order, bool canDispatch) {
    final bool done = _afterFinish.contains(order.status);
    final bool current = order.status == 'InProgress';
    final bool enabled = current && canDispatch && order.allows('finish');

    final List<Widget> children = <Widget>[
      _StepTitle(number: 1, done: done, current: current, title: t('dispatch.close.step1')),
    ];
    if (done) {
      children.add(Text(t('dispatch.close.step1Done'), style: TextStyle(fontSize: 13, color: AppColors.textMuted)));
    } else if (!current) {
      children.add(
        Text(t('dispatch.close.step1NotYet'), style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
      );
    } else if (canDispatch) {
      children.add(
        FilledButton(
          onPressed: (_busy || !enabled)
              ? null
              : () {
                  _run(() {
                    return finishOrder(widget.orderId);
                  });
                },
          child: Text(t('dispatch.close.step1')),
        ),
      );
    } else {
      children.add(Text(t('dispatch.close.noPermission'), style: TextStyle(fontSize: 13, color: AppColors.textMuted)));
    }
    return _StepCard(current: current, dimmed: done || !current, children: children);
  }

  // Bước 2: chốt phát sinh
  Widget _buildStep2(CloseOrder order, bool canEdit, bool canApprove) {
    final bool done = _afterFinalize.contains(order.status);
    final bool current = order.status == 'AwaitingFinalization';

    final List<Widget> children = <Widget>[
      _StepTitle(number: 2, done: done, current: current, title: t('dispatch.close.step2')),
      _MoneyRow(title: t('dispatch.close.quoted'), value: formatMoney(order.quotedAmount)),
    ];

    if (order.extraCharges.isNotEmpty) {
      final List<Widget> charges = <Widget>[];
      for (final ExtraCharge charge in order.extraCharges) {
        charges.add(_buildCharge(charge, current && canEdit && order.allows('confirm')));
      }
      children.add(
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border.symmetric(horizontal: BorderSide(color: AppColors.fillSoft)),
          ),
          child: Column(children: charges),
        ),
      );
    } else {
      children.add(Text(t('dispatch.close.noExtra'), style: TextStyle(fontSize: 13, color: AppColors.textMuted)));
    }

    children.add(
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(t('dispatch.close.total'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          Text(formatMoney(order.totalAmount), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ],
      ),
    );

    if (done) {
      children.add(Text(t('dispatch.close.step2Done'), style: TextStyle(fontSize: 13, color: AppColors.textMuted)));
    } else if (!current) {
      children.add(
        Text(t('dispatch.close.notYet'), style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
      );
    } else {
      if (canApprove) {
        children.add(
          FilledButton(
            onPressed: (_busy || !order.allows('finalize'))
                ? null
                : () {
                    _run(() {
                      return finalizeOrder(widget.orderId);
                    });
                  },
            child: Text(t('dispatch.close.finalize')),
          ),
        );
      } else {
        children.add(
          Text(t('dispatch.close.finalizeRole'), style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
        );
      }
      children.add(
        Text(
          t('dispatch.close.finalizeNote'),
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      );
    }

    return _StepCard(current: current, dimmed: done || !current, children: children);
  }

  Widget _buildCharge(ExtraCharge charge, bool canConfirm) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(charge.description, style: const TextStyle(fontSize: 14))),
              const SizedBox(width: 8),
              Text(formatMoney(charge.amount), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: charge.confirmedWithCustomer ? AppColors.okBackground : AppColors.warnBackground,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  charge.confirmedWithCustomer ? t('dispatch.close.confirmed') : t('dispatch.close.unconfirmed'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: charge.confirmedWithCustomer ? AppColors.okText : AppColors.warnText,
                  ),
                ),
              ),
              if (!charge.confirmedWithCustomer && canConfirm)
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () {
                          _run(() {
                            return confirmExtraCharge(widget.orderId, charge.id);
                          });
                        },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    foregroundColor: AppColors.navy,
                    side: BorderSide(color: AppColors.inputBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  child: Text(t('dispatch.close.confirmed')),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // Bước 3: xuất hóa đơn
  Widget _buildStep3(CloseOrder order, bool canInvoice) {
    final bool done = order.status == 'Invoiced';
    final bool current = order.status == 'Finalized';

    final List<Widget> children = <Widget>[
      _StepTitle(number: 3, done: done, current: current, title: t('dispatch.close.step3')),
    ];

    if (done) {
      children.add(Text(t('dispatch.close.step3Done'), style: TextStyle(fontSize: 13, color: AppColors.textMuted)));
    } else if (!current) {
      children.add(Text(t('dispatch.close.step3Locked'), style: TextStyle(fontSize: 13, color: AppColors.textMuted)));
    } else if (!canInvoice) {
      children.add(Text(t('dispatch.close.noInvoicePermission'), style: TextStyle(fontSize: 13, color: AppColors.textMuted)));
    } else {
      children.add(Text(t('dispatch.close.invoiceNumber'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.label)));
      children.add(
        TextField(
          controller: _invoiceController,
          enabled: !_busy,
          decoration: InputDecoration(hintText: t('dispatch.close.invoiceHint'), errorText: _invoiceError.isEmpty ? null : _invoiceError),
        ),
      );
      children.add(
        FilledButton(
          onPressed: (_busy || !order.allows('invoice'))
              ? null
              : () {
                  _run(() {
                    return invoiceOrder(widget.orderId, _invoiceController.text.trim());
                  });
                },
          child: Text(t('dispatch.close.invoiceButton')),
        ),
      );
      children.add(
        Text(
          t('dispatch.close.invoiceNote'),
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      );
    }

    return _StepCard(current: current, dimmed: done || !current, children: children);
  }
}

// Khung một bước: bước đang làm có viền xanh đậm, bước xong hoặc chưa tới thì mờ
class _StepCard extends StatelessWidget {
  final bool current;
  final bool dimmed;
  final List<Widget> children;

  const _StepCard({required this.current, required this.dimmed, required this.children});

  @override
  Widget build(BuildContext context) {
    final List<Widget> spaced = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) {
        spaced.add(const SizedBox(height: 8));
      }
      spaced.add(children[i]);
    }
    return Opacity(
      opacity: dimmed ? 0.75 : 1,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: current ? AppColors.navy : AppColors.border, width: current ? 2 : 1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: spaced),
      ),
    );
  }
}

// Tiêu đề bước: vòng tròn số (xanh lá có dấu tích khi xong, xanh đậm khi đang làm, xám khi chưa tới)
class _StepTitle extends StatelessWidget {
  final int number;
  final bool done;
  final bool current;
  final String title;

  const _StepTitle({required this.number, required this.done, required this.current, required this.title});

  @override
  Widget build(BuildContext context) {
    Color background = AppColors.fillSoft;
    Color foreground = AppColors.label;
    if (done) {
      background = AppColors.okBackground;
      foreground = AppColors.okText;
    } else if (current) {
      background = AppColors.navy;
      foreground = Colors.white;
    }
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(color: background, shape: BoxShape.circle),
          child: done
              ? Icon(Icons.check, size: 14, color: foreground)
              : Center(
                  child: Text('$number', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: foreground)),
                ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
      ],
    );
  }
}

class _MoneyRow extends StatelessWidget {
  final String title;
  final String value;

  const _MoneyRow({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      ],
    );
  }
}
