// Chi tiết đơn: tổng quan (điểm dừng, ngày làm, cảnh báo, lịch sử), kiện hàng, giá và phát sinh.
// Đổi bước theo allowedActions của server, không tự suy từ bước đơn.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/ios.dart';
import '../auth/session_provider.dart';
import '../customers/customer_detail_screen.dart' show orderStatusPill;
import '../driver/driver_widgets.dart' show GlassSegmented, callPhone;
import '../driver/trip_map.dart' show stopColor;
import 'order_actions.dart';
import 'order_edit.dart';
import 'orders_api.dart';

class OrderDetailScreen extends ConsumerStatefulWidget {
  final String orderId;

  const OrderDetailScreen({super.key, required this.orderId});

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  // 0 Tổng quan, 1 Kiện hàng, 2 Giá và phát sinh
  int tab = 0;
  // Server trả đơn mới sau khi sửa phát sinh: dùng ngay, không tải lại
  OrderDetail? updated;
  bool chargeBusy = false;
  final GlobalKey moreButtonKey = GlobalKey();

  Future<void> reload() async {
    ref.invalidate(orderHistoryProvider(widget.orderId));
    try {
      final OrderDetail _ = await ref.refresh(orderDetailProvider(widget.orderId).future);
      // Có bản mới rồi mới bỏ bản đang hiện, không để số cũ nháy lại
      if (mounted) setState(() => updated = null);
    } catch (_) {
      // Lỗi mạng: giữ nguyên dữ liệu đang hiện
    }
  }

  Future<void> runAction(OrderDetail order, OrderActionDef def) async {
    final bool changed = await showOrderActionSheet(context, order, def);
    if (changed && mounted) await reload();
  }

  Future<void> openMoreActions(OrderDetail order, List<OrderActionDef> actions) async {
    final OrderActionDef? picked = await showIosActionSheet<OrderActionDef>(
      context,
      anchor: moreButtonKey.currentContext,
      options: <IosSheetOption<OrderActionDef>>[
        for (final OrderActionDef def in actions) IosSheetOption<OrderActionDef>(def, def.label, destructive: def.danger),
      ],
    );
    if (picked != null && mounted) await runAction(order, picked);
  }

  Future<void> openEdit(OrderDetail order) async {
    await context.push('/orders/${order.publicId}/edit');
    if (mounted) await reload();
  }

  Future<void> changeCharge(Future<OrderDetail> Function() send, String done) async {
    setState(() => chargeBusy = true);
    try {
      final OrderDetail order = await send();
      if (!mounted) return;
      setState(() => updated = order);
      showIosToast(context, done);
    } catch (e) {
      if (mounted) showIosToast(context, errorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => chargeBusy = false);
    }
  }

  Future<void> addCharge(OrderDetail order) async {
    final OrderDetail? result = await showAddExtraChargeSheet(context, order.publicId);
    if (result == null || !mounted) return;
    setState(() => updated = result);
    showIosToast(context, t('orderDetail.extraAdded'));
  }

  Future<void> removeCharge(OrderDetail order, OrderExtraCharge charge) async {
    final bool ok = await showIosConfirm(
      context,
      title: t('orderDetail.removeExtraTitle'),
      message: charge.description,
      action: t('orderDetail.removeExtra'),
    );
    if (ok && mounted) {
      await changeCharge(() => removeExtraCharge(order.publicId, charge.publicId), t('orderDetail.extraRemoved'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<OrderDetail> value = ref.watch(orderDetailProvider(widget.orderId));
    final OrderDetail? order = updated ?? value.value;
    if (order == null) {
      return IosPage(
        title: t('orders.title'),
        slivers: <Widget>[
          SliverFillRemaining(
            hasScrollBody: false,
            child: AsyncView<OrderDetail>(
              value: value,
              onRetry: () => ref.invalidate(orderDetailProvider(widget.orderId)),
              builder: (OrderDetail _) => const SizedBox.shrink(),
            ),
          ),
        ],
      );
    }
    final Session? session = ref.watch(sessionProvider).value;
    final bool canEdit = session?.can('Orders.Edit') ?? false;
    final List<OrderActionDef> more = allowedOrderActions(order.allowedActions, secondary: true);
    final bool showEdit = canEditOrder(order.status, session) || mustRequestEdit(order.status, session);
    return IosPage(
      title: order.orderCode,
      onRefresh: reload,
      trailing: more.isEmpty && !showEdit
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (showEdit)
                  IosGlassIconButton(
                    icon: CupertinoIcons.pencil,
                    nativeSymbol: 'pencil',
                    tooltip: mustRequestEdit(order.status, session) ? t('orderDetail.requestEdit') : t('orderDetail.edit'),
                    onPressed: () => openEdit(order),
                  ),
                if (showEdit && more.isNotEmpty) const SizedBox(width: 8),
                if (more.isNotEmpty)
                  KeyedSubtree(
                    key: moreButtonKey,
                    child: IosGlassIconButton(
                      icon: CupertinoIcons.ellipsis,
                      nativeSymbol: 'ellipsis',
                      tooltip: t('orders.moreActions'),
                      onPressed: () => openMoreActions(order, more),
                      menu: <NativeMenuItem>[
                        for (final OrderActionDef def in more) NativeMenuItem(def.label, symbol: def.symbol, destructive: def.danger),
                      ],
                      onMenu: (int index) => runAction(order, more[index]),
                    ),
                  ),
              ],
            ),
      slivers: <Widget>[
        SliverToBoxAdapter(child: _Header(order: order, session: session, onAction: (OrderActionDef def) => runAction(order, def))),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: GlassSegmented(
              labels: <String>[
                t('orderDetail.tabOverview'),
                t('orderDetail.tabCargo', <String, Object?>{'count': order.totalCargosCount}),
                t('orderDetail.tabMoney'),
              ],
              selected: tab,
              onChanged: (int index) => setState(() => tab = index),
            ),
          ),
        ),
        if (tab == 0)
          ..._overview(order, session)
        else if (tab == 1)
          ..._cargos(order)
        else
          ..._money(order, canEdit),
      ],
    );
  }

  List<Widget> _overview(OrderDetail order, Session? session) {
    return <Widget>[
      if (order.oversizeWarnings.isNotEmpty)
        SliverToBoxAdapter(
          child: IosGroup(
            header: t('orderDetail.warnings'),
            headerIcon: CupertinoIcons.exclamationmark_triangle_fill,
            footer: order.oversizeAcknowledgedByName == null
                ? t('orderDetail.warningsFooter')
                : t('orderDetail.warningsAcknowledged', <String, Object?>{'name': order.oversizeAcknowledgedByName}),
            children: <Widget>[
              for (final OrderWarning warning in order.oversizeWarnings) _WarningRow(warning: warning),
            ],
          ),
        ),
      SliverToBoxAdapter(
        child: IosGroup(
          header: t('orderDetail.stops'),
          headerIcon: CupertinoIcons.location_solid,
          footer: order.routeWarning,
          dividerIndent: 58,
          children: <Widget>[
            for (final OrderStop stop in order.stops) _StopRow(stop: stop),
            if (order.hasCoordinates)
              IosRow(
                icon: CupertinoIcons.map_fill,
                iconColor: IosColors.blue,
                title: t('orderDetail.viewMap'),
                value: order.totalDistanceKm > 0 ? '${formatNumber(order.totalDistanceKm)} km' : null,
                onTap: () => context.push('/orders/${order.publicId}/map'),
              ),
          ],
        ),
      ),
      SliverToBoxAdapter(
        child: IosGroup(
          header: t('orderDetail.workDays'),
          headerIcon: CupertinoIcons.calendar,
          children: <Widget>[
            if (order.workDays.isEmpty) _PlainRow(text: t('orderDetail.noWorkDays')),
            for (final OrderWorkDay day in order.workDays)
              IosRow(
                title: formatDate(day.workDate),
                subtitle: day.note,
                value: '${_shortTime(day.startTime)} – ${_shortTime(day.endTime)}${day.isOvernight ? ' ${t('orderDetail.overnight')}' : ''}',
                chevron: false,
              ),
          ],
        ),
      ),
      if ((order.notes ?? '').isNotEmpty)
        SliverToBoxAdapter(
          child: IosGroup(header: t('orderDetail.notes'), headerIcon: CupertinoIcons.doc_text_fill, children: <Widget>[_PlainRow(text: order.notes!)]),
        ),
      SliverToBoxAdapter(child: _Links(order: order, session: session, onTripsClosed: reload)),
      SliverToBoxAdapter(child: _History(orderId: order.publicId)),
    ];
  }

  List<Widget> _cargos(OrderDetail order) {
    return <Widget>[
      SliverToBoxAdapter(
        child: IosGroup(
          headerIcon: CupertinoIcons.cube_box_fill,
          header: t('orderDetail.cargoSummary', <String, Object?>{
            'count': order.totalCargosCount,
            'weight': formatKg(order.totalWeightKg),
            'volume': formatNumber(order.totalVolumeM3),
          }),
          children: <Widget>[
            if (order.cargos.isEmpty) _PlainRow(text: t('orderDetail.noCargo')),
            for (final OrderCargo cargo in order.cargos) _CargoRow(cargo: cargo),
          ],
        ),
      ),
    ];
  }

  List<Widget> _money(OrderDetail order, bool canEdit) {
    final bool isFinal = order.finalAmount != null;
    final bool editable = order.extrasEditable && canEdit;
    return <Widget>[
      SliverToBoxAdapter(
        child: IosGroup(
          header: t('orderDetail.quote'),
          headerIcon: CupertinoIcons.tag_fill,
          footer: isFinal
              ? ((order.invoiceNumber ?? '').isEmpty
                  ? t('orderDetail.finalNote')
                  : t('orderDetail.finalNoteInvoice', <String, Object?>{'number': order.invoiceNumber}))
              : null,
          children: <Widget>[
            IosRow(title: t('orderDetail.quotedAmount'), value: order.quotedAmount == null ? t('orderDetail.notEntered') : formatMoney(order.quotedAmount), chevron: false),
            IosRow(title: t('orderDetail.extras'), value: formatMoney(order.extraChargesTotal), chevron: false),
            IosRow(
              title: isFinal ? t('orderDetail.finalTotal') : t('orderDetail.total'),
              trailing: Text(
                formatMoney(isFinal ? order.finalAmount : order.totalAmount),
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text),
              ),
              chevron: false,
            ),
          ],
        ),
      ),
      SliverToBoxAdapter(
        child: IosGroup(
          header: t('orderDetail.extras'),
          headerIcon: CupertinoIcons.plus_circle_fill,
          footer: t('orderDetail.extrasFooter'),
          children: <Widget>[
            if (order.extraCharges.isEmpty) _PlainRow(text: t('orderDetail.noExtras')),
            for (final OrderExtraCharge charge in order.extraCharges)
              _ChargeRow(
                charge: charge,
                busy: chargeBusy,
                onConfirm: editable && !charge.confirmedWithCustomer
                    ? () => changeCharge(() => confirmExtraCharge(order.publicId, charge.publicId), t('orderDetail.extraConfirmed'))
                    : null,
                onRemove: editable ? () => removeCharge(order, charge) : null,
              ),
            if (editable)
              IosRow(
                icon: CupertinoIcons.add,
                iconColor: IosColors.green,
                title: t('orderDetail.addExtra'),
                onTap: () => addCharge(order),
              ),
          ],
        ),
      ),
      SliverToBoxAdapter(
        child: IosGroup(
          header: t('orderDetail.referenceCost'),
          headerIcon: CupertinoIcons.chart_bar_alt_fill,
          footer: <String>[
            t('orderDetail.referenceNote'),
            if (order.fuelWarning != null) order.fuelWarning!,
            if (order.tollClassAssumed) t('orderDetail.tollAssumed'),
          ].join('\n'),
          children: <Widget>[
            IosRow(title: t('orderDetail.distance'), value: '${formatNumber(order.totalDistanceKm)} km', chevron: false),
            IosRow(title: t('orderDetail.fuelCost'), value: formatMoney(order.estimatedFuelCost), chevron: false),
            IosRow(title: t('orderDetail.tollCost'), value: formatMoney(order.tollCost), chevron: false),
          ],
        ),
      ),
    ];
  }
}

// "07:30:00" → "07:30"
String _shortTime(String time) => time.length >= 5 ? time.substring(0, 5) : time;

class _Header extends StatelessWidget {
  final OrderDetail order;
  final Session? session;
  final ValueChanged<OrderActionDef> onAction;

  const _Header({required this.order, required this.session, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final List<OrderActionDef> primary = allowedOrderActions(order.allowedActions, secondary: false);
    final String? lockedNote = switch (order.status) {
      'Invoiced' => t('orders.lockedInvoiced'),
      'Cancelled' => (order.cancelReason ?? '').isEmpty
          ? t('orders.lockedCancelled')
          : t('orders.cancelledReason', <String, Object?>{'reason': order.cancelReason}),
      _ => null,
    };
    final bool canOpenCustomer = order.customerId != null && (session?.can('Customers.View') ?? false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              orderStatusPill(order.status),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t('orders.createdOn', <String, Object?>{'date': formatDateTime(order.createdAt)}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(color: AppColors.raised, borderRadius: BorderRadius.circular(22)),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: CupertinoButton(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                    alignment: Alignment.centerLeft,
                    onPressed: canOpenCustomer ? () => context.push('/customers/${order.customerId}') : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          order.customerName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text),
                        ),
                        if (order.customerPhone.isNotEmpty)
                          Text(order.customerPhone, style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel)),
                      ],
                    ),
                  ),
                ),
                if (order.customerPhone.isNotEmpty) _CallButton(phone: order.customerPhone),
                const SizedBox(width: 8),
              ],
            ),
          ),
          if (lockedNote != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(lockedNote, style: TextStyle(fontSize: 14, color: order.status == 'Cancelled' ? IosColors.red : IosColors.secondaryLabel, height: 1.35)),
          ],
          for (int index = 0; index < primary.length; index++) ...<Widget>[
            const SizedBox(height: 12),
            if (index == 0)
              IosPillButton(label: primary[index].label, onPressed: () => onAction(primary[index]))
            else
              _SecondaryPill(label: primary[index].label, onPressed: () => onAction(primary[index])),
          ],
        ],
      ),
    );
  }
}

class _SecondaryPill extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _SecondaryPill({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Container(
        height: 50,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.raised, borderRadius: BorderRadius.circular(999)),
        child: Text(label, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: IosColors.blue)),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final String phone;

  const _CallButton({required this.phone});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: t('common.call'),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: () => callPhone(context, phone),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: IosColors.green.withValues(alpha: 0.14), shape: BoxShape.circle),
          child: Icon(CupertinoIcons.phone_fill, size: 19, color: IosColors.green),
        ),
      ),
    );
  }
}

class _PlainRow extends StatelessWidget {
  final String text;

  const _PlainRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: Text(text, style: TextStyle(fontSize: 15, color: IosColors.secondaryLabel, height: 1.35)),
      ),
    );
  }
}

class _WarningRow extends StatelessWidget {
  final OrderWarning warning;

  const _WarningRow({required this.warning});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(CupertinoIcons.exclamationmark_triangle_fill, size: 18, color: warning.isDanger ? IosColors.red : IosColors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(warning.message, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.3)),
                if ((warning.legalBasis ?? '').isNotEmpty)
                  Text(warning.legalBasis!, style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StopRow extends StatelessWidget {
  final OrderStop stop;

  const _StopRow({required this.stop});

  @override
  Widget build(BuildContext context) {
    final String phone = stop.contactPhone ?? '';
    final String contact = <String>[stop.contactName ?? '', phone].where((String part) => part.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: stopColor(stop.kind), shape: BoxShape.circle),
            child: Text('${stop.sequence}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(tEnum('stopKind', stop.kind), style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel)),
                Text(stop.address, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.text, height: 1.3)),
                if (contact.isNotEmpty) Text(contact, style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel, height: 1.4)),
                if ((stop.note ?? '').isNotEmpty) Text(stop.note!, style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel, height: 1.3)),
              ],
            ),
          ),
          if (phone.isNotEmpty) _CallButton(phone: phone),
        ],
      ),
    );
  }
}

class _CargoRow extends StatelessWidget {
  final OrderCargo cargo;

  const _CargoRow({required this.cargo});

  @override
  Widget build(BuildContext context) {
    final List<String> tags = <String>[
      if (cargo.isFragile) t('orderDetail.fragile'),
      if (cargo.doNotStack) t('orderDetail.doNotStack'),
    ];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: Text(cargo.cargoName, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.3))),
              const SizedBox(width: 8),
              Text('× ${cargo.quantity}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: IosColors.secondaryLabel)),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${formatKg(cargo.weightKg)} · ${formatSizeMm(cargo.lengthMm, cargo.widthMm, cargo.heightMm)}',
            style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel),
          ),
          if (tags.isNotEmpty) Text(tags.join(' · '), style: TextStyle(fontSize: 13, color: IosColors.orange, height: 1.4)),
        ],
      ),
    );
  }
}

class _ChargeRow extends StatelessWidget {
  final OrderExtraCharge charge;
  final bool busy;
  final VoidCallback? onConfirm;
  final VoidCallback? onRemove;

  const _ChargeRow({required this.charge, required this.busy, required this.onConfirm, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: Text(charge.description, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.3))),
              const SizedBox(width: 8),
              Text(formatMoney(charge.amount), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${charge.createdByName ?? '—'} · ${formatDateTime(charge.createdAt)}',
            style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel),
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Icon(
                charge.confirmedWithCustomer ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.clock_fill,
                size: 16,
                color: charge.confirmedWithCustomer ? IosColors.green : IosColors.orange,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  charge.confirmedWithCustomer ? t('orderDetail.extraAgreed') : t('orderDetail.extraNotAgreed'),
                  style: TextStyle(fontSize: 13, color: charge.confirmedWithCustomer ? AppColors.okText : AppColors.warnText),
                ),
              ),
              if (onConfirm != null)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(44, 34),
                  onPressed: busy ? null : onConfirm,
                  child: Text(t('orderDetail.extraConfirm'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: IosColors.blue)),
                ),
              if (onRemove != null)
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(36, 34),
                  onPressed: busy ? null : onRemove,
                  child: Icon(CupertinoIcons.trash, size: 19, color: IosColors.red),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Từ khi khách xác nhận là xếp được xe (BR-DSP-002): gán xong mới chốt lịch, tài xế thấy chuyến ngay khi chốt
bool orderShowsTrips(String status) {
  return const <String>{'CustomerConfirmed', 'Scheduled', 'InProgress', 'AwaitingFinalization', 'Finalized', 'Invoiced'}.contains(status);
}

class _Links extends StatelessWidget {
  final OrderDetail order;
  final Session? session;
  final Future<void> Function() onTripsClosed;

  const _Links({required this.order, required this.session, required this.onTripsClosed});

  @override
  Widget build(BuildContext context) {
    final bool showPlan = session?.can('Packing.View') ?? false;
    final bool showTrips = orderShowsTrips(order.status);
    if (!showPlan && !showTrips) return const SizedBox.shrink();
    return IosGroup(
      dividerIndent: 62,
      children: <Widget>[
        if (showPlan)
          IosRow(
            icon: CupertinoIcons.cube_box_fill,
            iconColor: IosColors.orange,
            title: t('orderDetail.plan'),
            onTap: () => context.push('/orders/${order.publicId}/plan'),
          ),
        if (showTrips)
          IosRow(
            icon: Icons.local_shipping,
            iconColor: IosColors.blue,
            title: t('orderDetail.trips'),
            // Màn chuyến có thể chốt lịch: quay về thì tải lại để nút đổi bước đúng trạng thái mới
            onTap: () async {
              await context.push('/orders/${order.publicId}/dispatch-trips');
              await onTripsClosed();
            },
          ),
      ],
    );
  }
}

class _History extends ConsumerWidget {
  final String orderId;

  const _History({required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<OrderHistoryItem>? history = ref.watch(orderHistoryProvider(orderId)).value;
    if (history == null) return const SizedBox.shrink();
    return IosGroup(
      header: t('orderDetail.history'),
      headerIcon: CupertinoIcons.clock_fill,
      children: <Widget>[
        if (history.isEmpty) _PlainRow(text: t('orderDetail.noHistory')),
        for (final OrderHistoryItem item in history) _HistoryRow(item: item),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final OrderHistoryItem item;

  const _HistoryRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final String to = tEnum('orderStatus', item.toStatus);
    final String title = item.action == 'Edit'
        ? t('orderDetail.historyEdit', <String, Object?>{'status': to})
        : (item.fromStatus == null ? to : '${tEnum('orderStatus', item.fromStatus)} → $to');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.text, height: 1.3)),
          Text(
            '${item.actorName ?? t('orderDetail.system')} · ${formatDateTime(item.occurredAt)}',
            style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel, height: 1.4),
          ),
          if ((item.reason ?? '').isNotEmpty)
            Text(t('orderDetail.historyReason', <String, Object?>{'text': item.reason}), style: TextStyle(fontSize: 13, color: AppColors.text, height: 1.35)),
          if ((item.note ?? '').isNotEmpty)
            Text(t('orderDetail.historyNote', <String, Object?>{'text': item.note}), style: TextStyle(fontSize: 13, color: AppColors.text, height: 1.35)),
        ],
      ),
    );
  }
}
