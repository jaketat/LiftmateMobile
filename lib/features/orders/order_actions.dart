// Các hành động đổi bước đơn và form thêm phát sinh, mở dạng sheet từ dưới lên.
// Nút hiện hay không do server quyết (allowedActions đã tính theo bước và quyền); bảng này chỉ lo chữ và ô nhập.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/call.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ios.dart';
import '../driver/account_api.dart' show newIdempotencyKey;
import 'orders_api.dart';

enum OrderActionField { none, note, reason, invoiceNumber }

class OrderActionDef {
  final String key;
  // Đuôi đường dẫn API: POST /orders/{id}/{path}
  final String path;
  final OrderActionField field;
  // Ô nhập bắt buộc
  final bool required;
  // Nằm trong menu "…" thay vì nút chính
  final bool secondary;
  final bool danger;
  // SF Symbol trong menu "…"
  final String? symbol;

  const OrderActionDef(
    this.key,
    this.path, {
    this.field = OrderActionField.none,
    this.required = false,
    this.secondary = false,
    this.danger = false,
    this.symbol,
  });

  String get label => t('orderAction.$key');
  String get description => t('orderAction.$key.description');
}

const List<OrderActionDef> orderActionDefs = <OrderActionDef>[
  OrderActionDef('sendQuote', 'send-quote'),
  OrderActionDef('confirm', 'confirm', field: OrderActionField.note),
  OrderActionDef('schedule', 'schedule'),
  OrderActionDef('start', 'start'),
  OrderActionDef('finish', 'finish'),
  OrderActionDef('finalize', 'finalize'),
  OrderActionDef('invoice', 'invoice', field: OrderActionField.invoiceNumber, required: true),
  OrderActionDef('reopenQuote', 'reopen-quote', field: OrderActionField.reason, required: true, secondary: true, symbol: 'arrow.uturn.backward'),
  OrderActionDef('cancel', 'cancel', field: OrderActionField.reason, required: true, secondary: true, danger: true, symbol: 'xmark.circle'),
];

/// Các hành động người xem làm được, theo thứ tự của bảng. Hành động lạ từ server thì bỏ qua.
List<OrderActionDef> allowedOrderActions(List<String> allowed, {required bool secondary}) {
  return <OrderActionDef>[
    for (final OrderActionDef def in orderActionDefs)
      if (allowed.contains(def.key) && def.secondary == secondary) def,
  ];
}

/// Đang mở sheet form. Sheet cao đè lên nút native của trang, bóng nút native lại vẽ đè lên sheet,
/// nên trong lúc này trang đổi sang nút Flutter (bọc NativeViewsPause)
final ValueNotifier<bool> orderFormSheetOpen = ValueNotifier<bool>(false);

/// Mở sheet form từ dưới lên. [dismissible] tắt: chạm ngoài hay kéo xuống không đóng, để khỏi mất chữ đang gõ
Future<T?> showOrderFormSheet<T>(BuildContext context, Widget child, {bool dismissible = true}) async {
  orderFormSheetOpen.value = true;
  try {
    return await showModalBottomSheet<T>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: dismissible,
      enableDrag: dismissible,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (BuildContext context) => child,
    );
  } finally {
    orderFormSheetOpen.value = false;
  }
}

class OrderFormSheet extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const OrderFormSheet({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        child: ColoredBox(
          color: AppColors.surface,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.paddingOf(context).bottom + 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text, letterSpacing: -0.3)),
                const SizedBox(height: 8),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OrderSheetField extends StatelessWidget {
  final String placeholder;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final int maxLines;
  final int? maxLength;
  // Địa chỉ, tên KCN: tắt tự sửa, iOS đổi "kcn" thành "ken"
  final bool autocorrect;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const OrderSheetField({
    required this.placeholder,
    required this.controller,
    required this.onChanged,
    this.maxLines = 1,
    this.maxLength,
    this.autocorrect = true,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoTextField(
      controller: controller,
      placeholder: placeholder,
      placeholderStyle: TextStyle(fontSize: 17, color: IosColors.tertiaryLabel),
      style: TextStyle(fontSize: 17, color: AppColors.text),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: AppColors.fillSoft, borderRadius: BorderRadius.circular(18)),
      minLines: maxLines == 1 ? null : 2,
      maxLines: maxLines,
      maxLength: maxLength,
      autocorrect: autocorrect,
      enableSuggestions: autocorrect,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
    );
  }
}

class OrderSheetError extends StatelessWidget {
  final String text;

  const OrderSheetError(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(text, style: TextStyle(fontSize: 14, color: IosColors.red, height: 1.35)),
    );
  }
}

/// Mở sheet xác nhận một hành động. Trả true khi đơn có thể đã đổi, màn gọi phải tải lại.
Future<bool> showOrderActionSheet(BuildContext context, OrderDetail order, OrderActionDef def) async {
  final bool? changed = await showOrderFormSheet<bool>(context, _ActionSheet(order: order, def: def));
  return changed ?? false;
}

class _ActionSheet extends StatefulWidget {
  final OrderDetail order;
  final OrderActionDef def;

  const _ActionSheet({required this.order, required this.def});

  @override
  State<_ActionSheet> createState() => _ActionSheetState();
}

class _ActionSheetState extends State<_ActionSheet> {
  final TextEditingController field = TextEditingController();
  late List<OrderWarning> warnings = widget.def.key == 'schedule' ? widget.order.oversizeWarnings : <OrderWarning>[];
  bool acknowledged = false;
  // Server vẫn đòi xác nhận (vd cảnh báo mới phát sinh) thì luôn cho tích, không để điều phối kẹt không chốt được lịch
  bool forceAck = false;
  bool noPod = false;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    if (widget.def.key == 'schedule') loadHazards();
    if (widget.def.key == 'finish' || widget.def.key == 'finalize') loadPod();
  }

  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  // Hai lượt tải dưới chỉ để cảnh báo thêm: lỗi mạng thì bỏ qua, server vẫn kiểm tra lúc gửi
  Future<void> loadHazards() async {
    try {
      final List<OrderWarning> hazards = await fetchOrderHazardWarnings(widget.order.publicId);
      if (mounted) setState(() => warnings = <OrderWarning>[...warnings, ...hazards]);
    } on ApiException {
      return;
    }
  }

  Future<void> loadPod() async {
    try {
      final int count = await fetchOrderPodCount(widget.order.publicId);
      if (mounted) setState(() => noPod = count == 0);
    } on ApiException {
      return;
    }
  }

  bool get needsAck => widget.def.key == 'schedule' && (warnings.isNotEmpty || forceAck);

  bool get ready => !busy && (!widget.def.required || field.text.trim().isNotEmpty) && (!needsAck || acknowledged);

  Future<void> run() async {
    setState(() {
      busy = true;
      error = null;
    });
    final String? text = field.text.trim().isEmpty ? null : field.text.trim();
    final OrderActionDef def = widget.def;
    try {
      await runOrderAction(
        widget.order.publicId,
        def.path,
        reason: def.field == OrderActionField.reason ? text : null,
        note: def.field == OrderActionField.note ? text : null,
        invoiceNumber: def.field == OrderActionField.invoiceNumber ? text : null,
        acknowledgeOversize: needsAck,
      );
      if (!mounted) return;
      showIosToast(context, t('orders.stepChanged', <String, Object?>{'action': def.label, 'code': widget.order.orderCode}));
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'ORDER_CHANGED_CONCURRENTLY' || e.code == 'INVALID_STATE_TRANSITION') {
        showIosToast(context, t('orders.changedByOther'), isError: true);
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        busy = false;
        if (e.code == 'OVERSIZE_ACKNOWLEDGEMENT_REQUIRED') forceAck = true;
        error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = errorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final OrderActionDef def = widget.def;
    return OrderFormSheet(
      title: '${def.label} · ${widget.order.orderCode}',
      children: <Widget>[
        Text(def.description, style: TextStyle(fontSize: 15, color: IosColors.secondaryLabel, height: 1.35)),
        if (needsAck) ...<Widget>[
          const SizedBox(height: 14),
          _WarningsBox(
            warnings: warnings,
            acknowledged: acknowledged,
            onAcknowledged: (bool value) => setState(() => acknowledged = value),
          ),
        ],
        if (noPod) ...<Widget>[
          const SizedBox(height: 14),
          _NoteBox(text: t('orderAction.noPod')),
        ],
        if (def.field != OrderActionField.none) ...<Widget>[
          const SizedBox(height: 14),
          OrderSheetField(
            placeholder: t('orderAction.$key.field'),
            controller: field,
            maxLines: def.field == OrderActionField.invoiceNumber ? 1 : 3,
            onChanged: (String _) => setState(() {}),
          ),
        ],
        if (error != null) OrderSheetError(error!),
        const SizedBox(height: 18),
        IosPillButton(
          label: def.label,
          color: def.danger ? IosColors.red : null,
          busy: busy,
          onPressed: ready ? run : null,
        ),
        CupertinoButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(false),
          // Không ghi "Hủy": đứng dưới nút "Hủy đơn" sẽ gây nhầm
          child: Text(t('common.back'), style: TextStyle(color: IosColors.blue)),
        ),
      ],
    );
  }

  String get key => widget.def.key;
}

class _WarningsBox extends StatelessWidget {
  final List<OrderWarning> warnings;
  final bool acknowledged;
  final ValueChanged<bool> onAcknowledged;

  const _WarningsBox({required this.warnings, required this.acknowledged, required this.onAcknowledged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.warnBackground, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(t('orderAction.warningsTitle'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.warnText)),
          const SizedBox(height: 6),
          for (final OrderWarning warning in warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• ${warning.message}',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.3,
                  fontWeight: warning.isDanger ? FontWeight.w600 : FontWeight.w400,
                  color: warning.isDanger ? IosColors.red : AppColors.text,
                ),
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(t('orderAction.acknowledge'), style: TextStyle(fontSize: 14, color: AppColors.text, height: 1.3)),
              ),
              const SizedBox(width: 10),
              CupertinoSwitch(value: acknowledged, activeTrackColor: IosColors.green, onChanged: onAcknowledged),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoteBox extends StatelessWidget {
  final String text;

  const _NoteBox({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.warnBackground, borderRadius: BorderRadius.circular(18)),
      child: Text(text, style: TextStyle(fontSize: 14, color: AppColors.warnText, height: 1.35)),
    );
  }
}

/// Chỉ cho gõ số, tự thêm dấu chấm nghìn
class MoneyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return TextEditingValue.empty;
    final String text = vietnameseNumberFormat.format(int.parse(digits));
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// Đọc số tiền từ ô đã có dấu chấm nghìn. Trống thì trả null.
int? parseMoneyInput(String text) => int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), ''));

/// Mở sheet thêm phát sinh. Trả đơn mới khi đã thêm, null khi bỏ.
Future<OrderDetail?> showAddExtraChargeSheet(BuildContext context, String orderId) {
  return showOrderFormSheet<OrderDetail>(context, _ExtraChargeSheet(orderId: orderId));
}

class _ExtraChargeSheet extends StatefulWidget {
  final String orderId;

  const _ExtraChargeSheet({required this.orderId});

  @override
  State<_ExtraChargeSheet> createState() => _ExtraChargeSheetState();
}

class _ExtraChargeSheetState extends State<_ExtraChargeSheet> {
  final TextEditingController description = TextEditingController();
  final TextEditingController amount = TextEditingController();
  // Giữ nguyên qua các lần bấm lại khi lỗi mạng: server không tạo trùng khoản
  final String idempotencyKey = newIdempotencyKey();
  bool confirmed = false;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    description.dispose();
    amount.dispose();
    super.dispose();
  }

  bool get ready => !busy && description.text.trim().isNotEmpty && (parseMoneyInput(amount.text) ?? 0) > 0;

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final OrderDetail updated = await addExtraCharge(
        widget.orderId,
        description: description.text.trim(),
        amount: parseMoneyInput(amount.text)!,
        confirmed: confirmed,
        idempotencyKey: idempotencyKey,
      );
      if (mounted) Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = errorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return OrderFormSheet(
      title: t('orderDetail.addExtra'),
      children: <Widget>[
        const SizedBox(height: 6),
        OrderSheetField(
          placeholder: t('orderDetail.extraDescription'),
          controller: description,
          onChanged: (String _) => setState(() {}),
        ),
        const SizedBox(height: 10),
        OrderSheetField(
          placeholder: t('orderDetail.extraAmount'),
          controller: amount,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[MoneyInputFormatter()],
          onChanged: (String _) => setState(() {}),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(child: Text(t('orderDetail.extraAgreed'), style: TextStyle(fontSize: 16, color: AppColors.text))),
            CupertinoSwitch(
              value: confirmed,
              activeTrackColor: IosColors.green,
              onChanged: (bool value) => setState(() => confirmed = value),
            ),
          ],
        ),
        if (error != null) OrderSheetError(error!),
        const SizedBox(height: 18),
        IosPillButton(label: t('orderDetail.addExtra'), busy: busy, onPressed: ready ? save : null),
        CupertinoButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: Text(t('common.cancel'), style: TextStyle(color: IosColors.blue)),
        ),
      ],
    );
  }
}
