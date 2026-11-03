// Danh sách đơn hàng: tìm mã đơn, tên khách, lọc theo bước, cuộn tải thêm.
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/paged_result.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ios.dart';
import '../../core/widgets/liftmate_intelligence.dart';
import '../auth/session_provider.dart';
import '../customers/customer_detail_screen.dart' show orderStatusPill;
import '../driver/trip_map.dart' show stopColor;
import 'order_ai_screen.dart' show orderAiDisabled;
import 'order_draft_store.dart';
import 'orders_api.dart';

const List<String> orderStatuses = <String>[
  'Draft',
  'Quoted',
  'CustomerConfirmed',
  'Scheduled',
  'InProgress',
  'AwaitingFinalization',
  'Finalized',
  'Invoiced',
  'Cancelled',
];

/// Ngày làm của đơn: một ngày, hoặc từ ngày đầu tới ngày cuối
String orderDaysText(String? from, String? to) {
  if (from == null) return t('orders.noDate');
  if (to == null || to.substring(0, 10) == from.substring(0, 10)) return formatDate(from);
  return '${formatDate(from)} – ${formatDate(to)}';
}

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  String search = '';
  String? status;
  List<OrderSummary> items = <OrderSummary>[];
  int page = 0;
  bool hasNext = true;
  bool loading = false;
  bool loadedOnce = false;
  Object? error;
  // Đổi bộ lọc khi lượt cũ chưa xong: kết quả lượt cũ bị bỏ
  int generation = 0;
  Timer? searchDebounce;
  // Nháp chưa đủ để lên server, chỉ nằm trên máy này
  SavedOrderDraft? localDraft;

  @override
  void initState() {
    super.initState();
    orderAiDisabled.value = false;
    reload();
  }

  @override
  void dispose() {
    searchDebounce?.cancel();
    super.dispose();
  }

  // Giữ danh sách cũ trên màn tới khi có kết quả mới, không nháy về vòng xoay
  Future<void> reload() {
    loadLocalDraft();
    return load(first: true);
  }

  Future<void> loadLocalDraft() async {
    final String? userId = ref.read(sessionProvider).value?.userId;
    final SavedOrderDraft? draft = userId == null || userId.isEmpty ? null : await OrderDraftStore.load(userId);
    if (mounted) setState(() => localDraft = draft);
  }

  Future<void> load({bool first = false}) async {
    if (!first && (loading || !hasNext)) return;
    final int current = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final PagedResult<OrderSummary> result = await fetchOrders(first ? 1 : page + 1, search: search, status: status);
      if (!mounted || current != generation) return;
      setState(() {
        items = first ? result.items : <OrderSummary>[...items, ...result.items];
        page = result.pageIndex;
        hasNext = result.hasNextPage;
        loading = false;
        loadedOnce = true;
      });
    } catch (e) {
      if (!mounted || current != generation) return;
      setState(() {
        error = e;
        loading = false;
        loadedOnce = true;
      });
    }
  }

  void onSearch(String text) {
    searchDebounce?.cancel();
    searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (text.trim() == search) return;
      search = text.trim();
      reload();
    });
  }

  Future<void> createOrder() async {
    await context.push('/orders/new');
    if (mounted) reload();
  }

  Future<void> createFromImage() async {
    await context.push('/orders/new/ai?then=form');
    if (mounted) reload();
  }

  Future<void> openOrder(OrderSummary order) async {
    await context.push('/orders/${order.publicId}');
    // Có thể vừa đổi bước trong màn chi tiết
    if (mounted) reload();
  }

  @override
  Widget build(BuildContext context) {
    return IosPage(
      title: t('orders.title'),
      inlineTitle: true,
      onRefresh: reload,
      trailing: Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? child) {
          if (!(ref.watch(sessionProvider).value?.can('Orders.Create') ?? false)) return const SizedBox.shrink();
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ValueListenableBuilder<bool>(
                valueListenable: orderAiDisabled,
                builder: (BuildContext context, bool disabled, Widget? child) => disabled
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: AiOrbButton(onPressed: createFromImage),
                      ),
              ),
              IosGlassIconButton(icon: CupertinoIcons.add, nativeSymbol: 'plus', tooltip: t('orderForm.title'), onPressed: createOrder),
            ],
          );
        },
      ),
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: CupertinoSearchTextField(
              placeholder: t('orders.searchHint'),
              style: TextStyle(color: AppColors.text),
              onChanged: onSearch,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: <Widget>[
                _StatusChip(label: t('orders.allSteps'), selected: status == null, onTap: () => pickStatus(null)),
                for (final String value in orderStatuses)
                  _StatusChip(label: tEnum('orderStatus', value), selected: status == value, onTap: () => pickStatus(value)),
              ],
            ),
          ),
        ),
        if (localDraft != null && search.isEmpty && (status == null || status == 'Draft'))
          SliverToBoxAdapter(
            child: IosGroup(
              children: <Widget>[
                IosRow(
                  icon: CupertinoIcons.pencil_outline,
                  iconColor: IosColors.orange,
                  title: t('orders.localDraft'),
                  subtitle: localDraft!.form.customerName.trim().isEmpty ? t('orders.localDraftNoCustomer') : localDraft!.form.customerName,
                  onTap: createOrder,
                ),
              ],
            ),
          ),
        ...listSlivers(),
      ],
    );
  }

  void pickStatus(String? value) {
    if (value == status) return;
    status = value;
    reload();
  }

  List<Widget> listSlivers() {
    if (!loadedOnce) {
      return const <Widget>[
        SliverFillRemaining(hasScrollBody: false, child: Center(child: CupertinoActivityIndicator(radius: 14))),
      ];
    }
    if (items.isEmpty && error != null) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: _CenterMessage(text: errorMessage(error!), action: t('common.retry'), onAction: reload),
        ),
      ];
    }
    if (items.isEmpty && !loading) {
      final bool filtered = search.isNotEmpty || status != null;
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: _CenterMessage(text: filtered ? t('orders.emptyFiltered') : t('orders.empty')),
        ),
      ];
    }
    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        sliver: SliverList.builder(
          itemCount: items.length + (hasNext || error != null ? 1 : 0),
          itemBuilder: (BuildContext context, int index) {
            if (index < items.length) {
              return _OrderCard(order: items[index], onTap: () => openOrder(items[index]));
            }
            if (error != null) {
              return CupertinoButton(onPressed: load, child: Text(t('common.retry')));
            }
            // Cuộn tới cuối thì tải trang tiếp. Đợi hết khung vì đang trong lúc dựng
            WidgetsBinding.instance.addPostFrameCallback((Duration _) {
              if (mounted) load();
            });
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CupertinoActivityIndicator()),
            );
          },
        ),
      ),
    ];
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _StatusChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: IosPressBounce(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? AppColors.navy : AppColors.raised,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final OrderSummary order;
  final VoidCallback onTap;

  const _OrderCard({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final num? amount = order.amount;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        pressedOpacity: 0.7,
        onPressed: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.raised,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x0F0C2858), blurRadius: 14, offset: Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      order.orderCode,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text),
                    ),
                  ),
                  const SizedBox(width: 8),
                  orderStatusPill(order.status),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                order.customerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text),
              ),
              if (order.pickupAddress.isNotEmpty || order.deliveryAddress.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                _RouteLine(color: stopColor('Pickup'), text: order.pickupAddress),
                const SizedBox(height: 6),
                _RouteLine(color: stopColor('Delivery'), text: order.deliveryAddress),
              ],
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Icon(CupertinoIcons.calendar, size: 15, color: AppColors.textMuted),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      orderDaysText(order.scheduledDate, order.scheduledEndDate),
                      style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                    ),
                  ),
                  if (amount != null)
                    Text(
                      formatMoney(amount),
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteLine extends StatelessWidget {
  final Color color;
  final String text;

  const _RouteLine({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 9,
          height: 9,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text.isEmpty ? '—' : text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: AppColors.text, height: 1.3),
          ),
        ),
      ],
    );
  }
}

class _CenterMessage extends StatelessWidget {
  final String text;
  final String? action;
  final VoidCallback? onAction;

  const _CenterMessage({required this.text, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(CupertinoIcons.doc_text, size: 44, color: IosColors.tertiaryLabel),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: IosColors.secondaryLabel, height: 1.35)),
          if (action != null) CupertinoButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}
