// Tạo và sửa đơn: một trang, các nhóm xếp theo luồng khách → điểm dừng → ngày làm → kiện → giá.
// Lưu nháp không bắt nhập đủ: thiếu khách, điểm dừng thì server không nhận nên nháp nằm trên máy, đủ mới tạo đơn Nháp trên server.
// Đủ kiện, ngày làm, giá thì lưu và gửi báo giá luôn.
// Trong lúc tạo, form tự lưu trên máy (order_draft_store.dart), thoát hay tắt app đều không mất.
// Theo CreateOrderPage, EditOrderPage của web. Chưa có ở đây: nhập kiện từ Excel, duyệt đề nghị sửa (làm trên web).
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vietmap_flutter_gl/vietmap_flutter_gl.dart' show LatLng;

import '../../core/api/call.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/labels.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/liftmate_intelligence.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/ios.dart';
import '../../core/widgets/page_transition.dart';
import '../auth/session_provider.dart';
import '../driver/account_api.dart' show newIdempotencyKey;
import '../driver/directions_logic.dart' show decodePolyline;
import '../driver/driver_api.dart' show TripStop;
import '../driver/trip_map.dart' show stopColor;
import '../fleet/fleet_api.dart' show Vehicle, vehicleProvider;
import 'order_actions.dart';
import 'order_ai_screen.dart' show orderAiDisabled;
import 'order_draft_store.dart';
import 'order_edit.dart';
import 'order_form.dart';
import 'order_map_screen.dart';
import 'order_new_sheets.dart';
import 'orders_api.dart';
import 'price_suggestion.dart';
import 'static_map.dart';
import 'stop_location_screen.dart';

const List<String> operatingProfiles = <String>['Balanced', 'MultiDrop', 'MaxVolume', 'Mountain'];

class OrderNewScreen extends ConsumerStatefulWidget {
  /// Kiện đã đọc từ ảnh, khi vào từ "Tạo đơn từ ảnh"
  final List<CargoDraft> initialCargos;

  /// Có đơn thì màn này là sửa đơn đó, không tự lưu nháp trên máy
  final OrderDetail? editing;

  const OrderNewScreen({super.key, this.initialCargos = const <CargoDraft>[], this.editing});

  @override
  ConsumerState<OrderNewScreen> createState() => _OrderNewScreenState();
}

/// Tải đơn rồi mở form sửa
class OrderEditLoader extends ConsumerStatefulWidget {
  final String orderId;

  const OrderEditLoader({super.key, required this.orderId});

  @override
  ConsumerState<OrderEditLoader> createState() => _OrderEditLoaderState();
}

class _OrderEditLoaderState extends ConsumerState<OrderEditLoader> {
  // Giữ bản đầu tiên: server trả bản mới giữa chừng không được đè lên chỗ đang sửa
  OrderDetail? order;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<OrderDetail> value = ref.watch(orderDetailProvider(widget.orderId));
    order ??= value.value;
    final OrderDetail? loaded = order;
    if (loaded != null) return OrderNewScreen(editing: loaded);
    return Scaffold(
      body: AsyncView<OrderDetail>(
        value: value,
        onRetry: () => ref.invalidate(orderDetailProvider(widget.orderId)),
        builder: (OrderDetail _) => const SizedBox.shrink(),
      ),
    );
  }
}

class _OrderNewScreenState extends ConsumerState<OrderNewScreen> {
  OrderFormData form = OrderFormData();
  final TextEditingController quoted = TextEditingController();
  final TextEditingController notes = TextEditingController();
  // Giữ nguyên qua các lần bấm lại khi lỗi mạng: server không tạo trùng đơn
  String idempotencyKey = newIdempotencyKey();
  // null: chưa bấm lưu, chưa hiện lỗi. Sau đó lỗi tính lại theo dữ liệu mới: sửa đúng là hết đỏ ngay
  bool? submittedForQuote;
  // 'draft' hoặc 'quote' trong lúc đang lưu
  String? busy;
  String? serverError;
  // Ước tính tuyến: khóa theo tọa độ nên không gọi lại Vietmap khi điểm không đổi
  String? routeKey;
  RouteEstimate? route;
  // Kết quả tuyến lần trước: đang tính lại thì thẻ giá gợi ý dùng tạm, không tắt rồi hiện lại
  RouteEstimate? lastRoute;
  String? routeError;
  bool routeLoading = false;
  // Xe dự kiến vừa chọn: dùng ngay cho giá gợi ý trong lúc chờ tải chi tiết xe
  Vehicle? pickedVehicle;
  // Tự lưu: null là tài khoản không xác định, khi đó không lưu
  String? userId;
  bool ready = false;
  bool finished = false;
  String? lastSavedBody;
  DateTime? restoredAt;
  Timer? saveTimer;
  // Đang sửa đơn: phần đang có trên server, và form lúc mới mở để biết có sửa gì chưa
  OrderEditBaseline? baseline;
  String? editOpenedAs;
  // Đã tự báo kết quả khi rời màn, không báo thêm "đã giữ nháp"
  bool leftWithToast = false;
  String? decodedFor;
  List<LatLng>? routeLine;
  // Đã kéo đổi thứ tự: báo ngay nếu thứ tự sai, không đợi tới lúc lưu
  bool reordered = false;
  final TextEditingController editReason = TextEditingController();
  bool triedReason = false;
  late final AppLifecycleListener lifecycle;

  @override
  void initState() {
    super.initState();
    final String? id = ref.read(sessionProvider).value?.userId;
    userId = id == null || id.isEmpty ? null : id;
    // Sắp vào nền là có thể bị hệ thống tắt: ghi ngay
    lifecycle = AppLifecycleListener(onInactive: saveNow, onHide: saveNow);
    restore();
  }

  bool get isEditing => widget.editing != null;

  String editSnapshot() => jsonEncode(<String, dynamic>{'form': form.toDraft(), 'quoted': quoted.text, 'notes': notes.text});

  bool get hasUnsavedEdits => isEditing && ready && editOpenedAs != editSnapshot();

  void openForEdit(OrderDetail order) {
    form = OrderFormData.fromOrder(order);
    quoted.text = order.quotedAmount == null ? '' : formatNumber(order.quotedAmount);
    notes.text = form.notes;
    baseline = OrderEditBaseline.of(form);
    editOpenedAs = editSnapshot();
    ready = true;
    // Như web: mở sửa là tính tuyến để có đủ thời gian, cao tốc, tiền dầu
    refreshRoute();
  }

  Future<void> restore() async {
    if (isEditing) {
      openForEdit(widget.editing!);
      return;
    }
    final SavedOrderDraft? saved = userId == null ? null : await OrderDraftStore.load(userId!);
    if (!mounted) return;
    setState(() {
      if (saved != null) {
        form = saved.form;
        idempotencyKey = saved.idempotencyKey;
        quoted.text = saved.quotedText;
        notes.text = saved.form.notes;
        // Bản nháp cũ chưa có đường vẽ: để tính lại
        routeKey = saved.route?.polyline == null ? null : saved.routeKey;
        route = routeKey == null ? null : saved.route;
        restoredAt = saved.savedAt ?? DateTime.now();
        lastSavedBody = currentDraft().encodeBody();
      }
      // Vào từ "Tạo đơn từ ảnh" khi đang có nháp: kiện mới thêm vào nháp đó
      form.cargos.addAll(widget.initialCargos);
      ready = true;
    });
    // Nháp có đủ tọa độ mà chưa có kết quả tuyến thì tính lại; đã có thì hàm này không gọi gì
    refreshRoute();
  }

  SavedOrderDraft currentDraft() {
    return SavedOrderDraft(form: form, idempotencyKey: idempotencyKey, quotedText: quoted.text, routeKey: routeKey, route: route);
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    if (ready && !finished) {
      saveTimer?.cancel();
      saveTimer = Timer(const Duration(milliseconds: 400), saveNow);
    }
  }

  /// Ghi bản đang nhập nếu có đổi; form trống thì xóa bản cũ
  void saveNow() {
    saveTimer?.cancel();
    final String? id = userId;
    if (isEditing || !ready || finished || id == null) return;
    form.quotedAmount = parseMoneyInput(quoted.text);
    form.notes = notes.text;
    if (!form.isDirty) {
      if (lastSavedBody != null) {
        lastSavedBody = null;
        OrderDraftStore.clear(id);
      }
      return;
    }
    final String body = currentDraft().encodeBody();
    if (body == lastSavedBody) return;
    lastSavedBody = body;
    OrderDraftStore.save(id, body);
  }

  /// Bỏ nháp đang tiếp tục, làm lại từ form trống
  Future<void> startOver() async {
    final bool discard = await showIosConfirm(
      context,
      title: t('orderForm.discardTitle'),
      message: t('orderForm.discardMessage'),
      action: t('orderForm.discard'),
      cancel: t('orderForm.keepEditing'),
    );
    if (!discard || !mounted) return;
    setState(() {
      form = OrderFormData();
      idempotencyKey = newIdempotencyKey();
      quoted.clear();
      notes.clear();
      submittedForQuote = null;
      serverError = null;
      routeKey = null;
      route = null;
      lastRoute = null;
      routeError = null;
      routeLoading = false;
      restoredAt = null;
    });
    saveNow();
  }

  @override
  void dispose() {
    saveNow();
    lifecycle.dispose();
    quoted.dispose();
    notes.dispose();
    editReason.dispose();
    super.dispose();
  }

  Map<String, String> get errors => submittedForQuote == null ? const <String, String>{} : form.validate(forQuote: submittedForQuote!);

  Future<void> refreshRoute() async {
    final Map<String, dynamic>? request = form.routeRequest();
    final String? key = request?.toString();
    if (key == routeKey) return;
    setState(() {
      routeKey = key;
      // Thiếu điểm hay tọa độ thì bỏ hẳn kết quả cũ; còn đủ thì giữ lại cho tới khi có kết quả mới
      lastRoute = request == null ? null : (route ?? lastRoute);
      route = null;
      routeError = null;
      routeLoading = request != null;
    });
    if (request == null) return;
    try {
      final RouteEstimate estimate = await estimateOrderRoute(request);
      if (mounted && key == routeKey) {
        setState(() {
          route = estimate;
          lastRoute = estimate;
          routeLoading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted && key == routeKey) {
        setState(() {
          routeError = e.code == 'ROUTE_NOT_FOUND' ? t('orderForm.routeNotFound') : e.message;
          lastRoute = null;
          routeLoading = false;
        });
      }
    }
  }

  Future<void> pickCustomer() async {
    final CustomerPick? pick = await showCustomerPickerSheet(context, form: form);
    if (pick == null || !mounted) return;
    setState(() {
      form.isNewCustomer = pick.isNew;
      form.customerId = pick.id;
      form.customerName = pick.name;
      form.customerPhone = pick.phone;
    });
  }

  // Điểm gần nhất đã có vị trí, để mở bản đồ đúng khu vực
  LatLng? nearStop(int index) {
    for (int i = index - 1; i >= 0; i--) {
      if (form.stops[i].hasCoordinates) return LatLng(form.stops[i].latitude!, form.stops[i].longitude!);
    }
    for (int i = index + 1; i < form.stops.length; i++) {
      if (form.stops[i].hasCoordinates) return LatLng(form.stops[i].latitude!, form.stops[i].longitude!);
    }
    return null;
  }

  Future<void> editStop(int index) async {
    // Điểm chưa có địa chỉ: chọn trên bản đồ trước, như Grab, rồi mới nhập người liên hệ
    if (stopMapAvailable && form.stops[index].address.trim().isEmpty) {
      final PickedLocation? picked = await pickStopLocation(context, kind: form.stops[index].kind, number: index + 1, near: nearStop(index));
      if (picked == null || !mounted) return;
      if (!picked.isManual) {
        setState(() {
          form.stops[index].address = picked.address;
          form.stops[index].latitude = picked.latitude;
          form.stops[index].longitude = picked.longitude;
        });
        refreshRoute();
      }
    }
    if (!mounted) return;
    final StopSheetResult? result = await showStopSheet(context, stop: form.stops[index], index: index, total: form.stops.length, near: nearStop(index));
    if (result == null || !mounted) return;
    setState(() {
      form.changeStops(() {
        if (result.delete) {
          form.stops.removeAt(index);
        } else {
          form.stops[index] = result.stop!;
        }
      });
    });
    refreshRoute();
  }

  void reorderStop(int oldIndex, int newIndex) {
    if (newIndex == oldIndex) return;
    setState(() {
      reordered = true;
      form.changeStops(() => form.stops.insert(newIndex, form.stops.removeAt(oldIndex)));
    });
    refreshRoute();
  }

  Future<void> addStop(String kind) async {
    final StopDraft stop = StopDraft(kind: kind);
    final int index = form.insertIndexFor(kind);
    final LatLng? near = nearStop(index);
    if (stopMapAvailable) {
      final PickedLocation? picked = await pickStopLocation(context, kind: kind, number: index + 1, near: near);
      if (picked == null || !mounted) return;
      if (!picked.isManual) {
        stop
          ..address = picked.address
          ..latitude = picked.latitude
          ..longitude = picked.longitude;
      }
    }
    if (!mounted) return;
    final StopSheetResult? result = await showStopSheet(context, stop: stop, index: index, total: form.stops.length + 1, near: near);
    if (result?.stop == null || !mounted) return;
    setState(() => form.changeStops(() => form.stops.insert(index, result!.stop!)));
    refreshRoute();
  }

  Future<void> pickNewStopKind() async {
    final String? kind = await showIosActionSheet<String>(
      context,
      options: <IosSheetOption<String>>[
        for (final String value in const <String>['Delivery', 'Pickup', 'Via']) IosSheetOption<String>(value, label(stopKindLabels, value)),
      ],
    );
    if (kind != null && mounted) addStop(kind);
  }

  Future<void> editWorkDay(int? index) async {
    final bool isNew = index == null;
    final WorkDaySheetResult? result = await showWorkDaySheet(context, day: isNew ? WorkDayDraft() : form.workDays[index], isNew: isNew);
    if (result == null || !mounted) return;
    setState(() {
      if (result.deleted) {
        form.workDays.removeAt(index!);
      } else if (isNew) {
        form.workDays.add(result.day!);
      } else {
        form.workDays[index] = result.day!;
      }
    });
  }

  Future<void> editCargo(int? index) async {
    final bool isNew = index == null;
    final CargoSheetResult? result = await showCargoSheet(context, cargo: isNew ? CargoDraft() : form.cargos[index], isNew: isNew, stops: form.stops);
    if (result == null || !mounted) return;
    setState(() {
      if (result.deleted) {
        form.cargos.removeAt(index!);
      } else if (isNew) {
        form.cargos.add(result.cargo!);
      } else {
        form.cargos[index] = result.cargo!;
      }
    });
  }

  Session? get session => ref.read(sessionProvider).value;

  Future<void> pickEstimationVehicle() async {
    final EstimationVehiclePick? pick = await showEstimationVehicleSheet(context, tractors: false, noneLabel: t('orderForm.estimationNone'));
    if (pick == null || !mounted) return;
    final bool trailer = pick.vehicle?.baseType == 'Trailer';
    setState(() {
      pickedVehicle = pick.vehicle;
      form.estimationVehicleId = pick.vehicle?.publicId;
      form.estimationVehicleLabel = pick.vehicle?.title;
      form.estimationIsTrailer = trailer;
      // Đổi sang xe không phải moóc thì bỏ đầu kéo
      if (!trailer) {
        form.estimationTractorId = null;
        form.estimationTractorLabel = null;
      }
    });
    refreshRoute();
  }

  Future<void> pickEstimationTractor() async {
    final EstimationVehiclePick? pick = await showEstimationVehicleSheet(context, tractors: true, noneLabel: t('orderForm.estimationTractorNone'));
    if (pick == null || !mounted) return;
    setState(() {
      form.estimationTractorId = pick.vehicle?.publicId;
      form.estimationTractorLabel = pick.vehicle?.title;
    });
    refreshRoute();
  }

  void recalculateRoute() {
    routeKey = null;
    refreshRoute();
  }

  Future<void> readWithAi() async {
    final List<CargoDraft>? cargos = await context.push<List<CargoDraft>>('/orders/new/ai');
    if (cargos != null && mounted) setState(() => form.cargos.addAll(cargos));
  }

  Future<void> pickProfile() async {
    final String? profile = await showIosActionSheet<String>(
      context,
      title: t('orderForm.profile'),
      options: <IosSheetOption<String>>[
        for (final String value in operatingProfiles) IosSheetOption<String>(value, tEnum('operatingProfile', value)),
      ],
    );
    if (profile != null && mounted) setState(() => form.operatingProfile = profile);
  }

  /// Lưu đơn đang sửa. Server luôn đòi điểm dừng hợp lệ, nên bước này vẫn phải kiểm tra
  Future<void> submitEdit({required bool forQuote}) async {
    final OrderDetail order = widget.editing!;
    setState(() {
      submittedForQuote = forQuote;
      serverError = null;
    });
    if (form.validate(forQuote: forQuote).isNotEmpty) {
      showIosToast(context, t('orderForm.fixErrors'), isError: true);
      return;
    }
    final OrderEditChanges changes = orderEditChanges(form, baseline!);
    if (changes.isEmpty && !forQuote) {
      showIosToast(context, t('orderForm.noChanges'));
      return;
    }
    if (needsEditReason && editReason.text.trim().isEmpty) {
      setState(() => triedReason = true);
      showIosToast(context, t('orderForm.fixErrors'), isError: true);
      return;
    }
    setState(() => busy = forQuote ? 'quote' : 'draft');
    try {
      final bool requested = await saveOrderEdits(form, order, baseline!, session: session, reason: editReason.text);
      String message = requested ? t('orderForm.editRequested') : t('orderForm.savedChanges', <String, Object?>{'code': order.orderCode});
      bool failed = false;
      if (forQuote) {
        try {
          await runOrderAction(order.publicId, 'send-quote');
        } on ApiException catch (e) {
          failed = true;
          message = t('orderForm.resendFailed', <String, Object?>{'code': order.orderCode, 'reason': e.message});
        }
      }
      if (!mounted) return;
      showIosToast(context, message, isError: failed);
      // Đã lưu xong: thoát không hỏi bỏ thay đổi
      setState(() {
        editOpenedAs = editSnapshot();
        busy = null;
      });
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = null;
        serverError = switch (e) {
          ApiException(code: 'ORDER_NOT_EDITABLE') => t('orderForm.orderNotEditable'),
          ApiException(code: 'ORDER_CHANGED_CONCURRENTLY') => t('orderForm.orderChanged'),
          ApiException(:final Map<String, String> fieldErrors) when fieldErrors.isNotEmpty => fieldErrors.values.first,
          _ => errorMessage(e),
        };
      });
      showIosToast(context, serverError!, isError: true);
    }
  }

  // Đơn đã khóa với người không có quyền sửa ở mọi bước: phần đổi được gửi thành đề nghị cho giám đốc duyệt
  bool get isEditRequest => isEditing && (mustRequestEdit(widget.editing!.status, session) || mustRequestWorkDays(widget.editing!.status, session));

  bool get cargoLocked => isEditing && !canEditOrder(widget.editing!.status, session);

  bool get repriceFinalized => isEditing && widget.editing!.status == 'Finalized' && parseMoneyInput(quoted.text) != widget.editing!.quotedAmount?.toInt();

  bool get needsEditReason {
    if (!isEditing) return false;
    form.quotedAmount = parseMoneyInput(quoted.text);
    form.notes = notes.text;
    final OrderDetail order = widget.editing!;
    return repriceFinalized || editNeedsApproval(orderEditChanges(form, baseline!), order.status, session);
  }

  Future<void> leaveEdit() async {
    if (hasUnsavedEdits) {
      final bool discard = await showIosConfirm(
        context,
        title: t('orderForm.discardChangesTitle'),
        message: t('orderForm.discardChangesMessage'),
        action: t('orderForm.discard'),
        cancel: t('orderForm.keepEditing'),
      );
      if (!discard || !mounted) return;
      setState(() => editOpenedAs = editSnapshot());
    }
    if (mounted) context.pop();
  }

  // Xếp thử 3D cần đơn có trên server: đơn mới thì lưu Nháp rồi mở kế hoạch xếp; đang sửa thì xếp theo kiện đã lưu
  Future<void> openPacking() async {
    if (isEditing) {
      if (hasUnsavedEdits) {
        showIosToast(context, t('orderForm.plan3dSaveFirst'));
        return;
      }
      context.push('/orders/${widget.editing!.publicId}/plan');
      return;
    }
    await submit(forQuote: false, thenPacking: true);
  }

  Future<void> submit({required bool forQuote, bool thenPacking = false}) async {
    FocusScope.of(context).unfocus();
    form.quotedAmount = parseMoneyInput(quoted.text);
    form.notes = notes.text;
    if (isEditing) return submitEdit(forQuote: forQuote);
    setState(() {
      // Lưu nháp không tô đỏ gì: thiếu thì để trên máy
      submittedForQuote = forQuote ? true : null;
      serverError = null;
    });
    if (form.validate(forQuote: forQuote).isNotEmpty) {
      if (thenPacking) {
        showIosToast(context, t('orderForm.plan3dNeedsBasics'), isError: true);
        return;
      }
      if (forQuote) {
        showIosToast(context, t('orderForm.fixErrors'), isError: true);
        return;
      }
      saveNow();
      leftWithToast = true;
      if (form.isDirty) showIosToast(context, t('orderForm.savedOnDevice'));
      context.pop();
      return;
    }
    setState(() => busy = forQuote ? 'quote' : 'draft');
    try {
      final OrderDetail order = await createOrder(form.toJson(), idempotencyKey: idempotencyKey);
      // Đơn đã có trên server, nháp hết việc. Giữ lại thì lần sau mở form sẽ tạo lại đúng đơn này.
      finished = true;
      saveTimer?.cancel();
      if (userId != null) OrderDraftStore.clear(userId!);
      if (!mounted) return;
      String message = t('orderForm.savedDraft', <String, Object?>{'code': order.orderCode});
      bool failed = false;
      if (forQuote) {
        try {
          await runOrderAction(order.publicId, 'send-quote');
          message = t('orderForm.savedQuoted', <String, Object?>{'code': order.orderCode});
        } on ApiException catch (e) {
          // Đơn đã lưu rồi: vẫn sang màn đơn, chỉ báo chưa gửi được báo giá
          failed = true;
          message = t('orderForm.savedQuoteFailed', <String, Object?>{'code': order.orderCode, 'reason': e.message});
        }
      }
      if (!mounted) return;
      // Số điện thoại trùng khách có sẵn: server gắn đơn vào khách đó, phải nói cho người tạo biết
      if (order.customerMatchedByPhone && (order.customerNotice ?? '').isNotEmpty) {
        message = '$message\n${order.customerNotice}';
      }
      showIosToast(context, message, isError: failed);
      if (thenPacking) {
        final GoRouter router = GoRouter.of(context);
        router.pushReplacement('/orders/${order.publicId}');
        router.push('/orders/${order.publicId}/plan');
        return;
      }
      context.pushReplacement('/orders/${order.publicId}');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        busy = null;
        serverError = e.fieldErrors.isEmpty ? e.message : e.fieldErrors.values.first;
      });
      showIosToast(context, serverError!, isError: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = null;
        serverError = errorMessage(e);
      });
      showIosToast(context, serverError!, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, String> errorMap = errors;
    final bool keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return PopScope(
      // Tạo đơn thì thoát thoải mái vì đã tự lưu; sửa đơn thì hỏi trước khi bỏ. Lúc đang gửi thì chặn
      canPop: busy == null && !hasUnsavedEdits,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          if (busy == null && isEditing) leaveEdit();
          return;
        }
        saveNow();
        if (!isEditing && !leftWithToast && form.isDirty && !finished) showIosToast(context, t('orderForm.draftKept'));
      },
      child: NativeViewsPause(
        paused: orderFormSheetOpen,
        child: IosPage(
        title: isEditing ? (isEditRequest ? t('orderForm.requestEditTitle') : t('orderForm.editTitle')) : t('orderForm.title'),
        onBack: busy != null ? () {} : (isEditing ? leaveEdit : () => context.pop()),
        bottom: keyboardOpen || !ready
            ? null
            : _SaveBar(
                busy: busy,
                draftLabel: isEditing ? (isEditRequest ? t('orderForm.sendEditRequest') : t('orderForm.saveChanges')) : t('orderForm.saveDraft'),
                quoteLabel: quoteLabel,
                onDraft: () => submit(forQuote: false),
                onQuote: () => submit(forQuote: true),
              ),
        slivers: <Widget>[
          if (!ready)
            const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: CupertinoActivityIndicator())),
          if (ready && restoredAt != null) SliverToBoxAdapter(child: _restoredBanner()),
          if (ready) ...<Widget>[
            SliverToBoxAdapter(child: _customerGroup(errorMap)),
            SliverToBoxAdapter(child: _stopsGroup(errorMap)),
            SliverToBoxAdapter(child: _routeGroup()),
            SliverToBoxAdapter(child: _workDaysGroup(errorMap)),
            SliverToBoxAdapter(child: _cargosGroup(errorMap)),
            SliverToBoxAdapter(child: _priceGroup(errorMap)),
            if (needsEditReason || isEditRequest) SliverToBoxAdapter(child: _reasonGroup()),
          ],
          if (serverError != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(serverError!, style: TextStyle(fontSize: 14, color: IosColors.red, height: 1.35)),
              ),
            ),
        ],
        ),
      ),
    );
  }

  // Sửa đơn: chỉ hiện nút báo giá khi đơn còn ở bước gửi được
  String? get quoteLabel {
    final OrderDetail? order = widget.editing;
    if (order == null) return t('orderForm.saveAndQuote');
    if (!order.allowedActions.contains('sendQuote')) return null;
    return order.status == 'Quoted' ? t('orderForm.saveAndResend') : t('orderForm.saveAndQuote');
  }

  Widget _restoredBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              t('orderForm.draftRestored', <String, Object?>{'time': formatDateTime(restoredAt!.toIso8601String())}),
              style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel, height: 1.35),
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(44, 36),
            onPressed: busy == null ? startOver : null,
            child: Text(t('orderForm.startOver'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: IosColors.red)),
          ),
        ],
      ),
    );
  }

  Widget _errorFooter(String? text) {
    return Text(text ?? '', style: TextStyle(fontSize: 13, color: IosColors.red, height: 1.35));
  }

  Widget _customerGroup(Map<String, String> errorMap) {
    final String? error = errorMap['customer'];
    final bool chosen = form.customerName.isNotEmpty;
    return IosGroup(
      header: t('orderForm.customer'),
      headerIcon: CupertinoIcons.person_fill,
      footerWidget: error != null
          ? _errorFooter(error)
          : (isEditing ? Text(t('orderForm.customerLocked'), style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel, height: 1.35)) : null),
      children: <Widget>[
        IosRow(
          title: chosen ? form.customerName : t('orderForm.chooseCustomer'),
          subtitle: chosen ? <String>[form.customerPhone, if (form.isNewCustomer) t('orderForm.customerNew')].where((String part) => part.isNotEmpty).join(' · ') : null,
          onTap: isEditing ? null : pickCustomer,
        ),
      ],
    );
  }

  List<LatLng>? get decodedRoute {
    final String? polyline = route?.polyline;
    if (polyline != decodedFor) {
      decodedFor = polyline;
      routeLine = polyline == null || polyline.isEmpty ? null : decodePolyline(polyline);
    }
    return routeLine;
  }

  void openRouteMap() {
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => Scaffold(
          body: RouteMapPage(
            title: t('orderForm.routeMapTitle'),
            route: decodedRoute,
            stops: <TripStop>[
              for (int index = 0; index < form.stops.length; index++)
                TripStop(
                  sequence: index + 1,
                  kind: form.stops[index].kind,
                  address: form.stops[index].address,
                  latitude: form.stops[index].latitude,
                  longitude: form.stops[index].longitude,
                  contactName: form.stops[index].contactName,
                  contactPhone: form.stops[index].contactPhone,
                  note: form.stops[index].note,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stopRows(Map<String, String> errorMap) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      buildDefaultDragHandles: false,
      itemCount: form.stops.length,
      onReorderItem: reorderStop,
      onReorderStart: (int index) => HapticFeedback.mediumImpact(),
      proxyDecorator: (Widget child, int index, Animation<double> animation) {
        return AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (BuildContext context, Widget? row) {
            final double lift = Curves.easeOut.transform(animation.value);
            return Transform.scale(
              scale: 1 + 0.02 * lift,
              child: Material(
                color: AppColors.surface,
                elevation: 10 * lift,
                shadowColor: const Color(0x660C2858),
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: row,
              ),
            );
          },
        );
      },
      itemBuilder: (BuildContext context, int index) {
        final StopDraft stop = form.stops[index];
        return ReorderableDelayedDragStartListener(
          key: ValueKey<String>(stop.key),
          index: index,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _StopDraftRow(
                stop: stop,
                number: index + 1,
                dragIndex: index,
                error: errorMap['stop.${stop.key}'] ?? errorMap['stop.${stop.key}.phone'],
                onTap: () => editStop(index),
              ),
              if (index < form.stops.length - 1)
                Padding(
                  padding: const EdgeInsets.only(left: 58),
                  child: Container(height: 0.5, color: IosColors.separator),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _stopsGroup(Map<String, String> errorMap) {
    final String? error = errorMap['stops'] ?? (reordered ? form.stopOrderError : null);
    return IosGroup(
      header: t('orderForm.stops'),
      headerIcon: CupertinoIcons.location_solid,
      footerWidget: error == null ? null : _errorFooter(error),
      dividerIndent: 58,
      children: <Widget>[
        // Có điểm là hiện bản đồ; từ 2 điểm thì có đường nối
        if (stopMapAvailable && form.stops.any((StopDraft stop) => stop.hasCoordinates))
          StaticRouteMap(
            height: 190,
            semanticLabel: t('orderForm.routeMapTitle'),
            route: decodedRoute,
            stops: <StaticMapStop>[
              for (int index = 0; index < form.stops.length; index++)
                if (form.stops[index].hasCoordinates)
                  StaticMapStop(
                    point: LatLng(form.stops[index].latitude!, form.stops[index].longitude!),
                    color: stopColor(form.stops[index].kind),
                    label: '${index + 1}',
                  ),
            ],
            onTap: openRouteMap,
          ),
        _stopRows(errorMap),
        if (form.stops.length < maxOrderStops)
          IosRow(icon: CupertinoIcons.add, iconColor: IosColors.green, title: t('orderForm.addStop'), onTap: pickNewStopKind),
      ],
    );
  }

  String routeDurationText(num minutes) {
    final int total = minutes.ceil();
    if (total < 60) return t('directions.minutes', <String, Object?>{'minutes': total});
    return t('directions.hoursMinutes', <String, Object?>{'hours': total ~/ 60, 'minutes': total % 60});
  }

  String? fuelBasisText(RouteEstimate estimate) {
    final num? price = estimate.fuelPricePerLiter;
    if (price == null || price <= 0) return null;
    final String? date = estimate.fuelPriceEffectiveDate;
    final String day = date != null && date.length >= 10 ? ', ${date.substring(8, 10)}/${date.substring(5, 7)}' : '';
    final num? consumption = estimate.fuelConsumptionPer100Km;
    final String per = consumption != null && consumption > 0 ? t('orderForm.fuelPer', <String, Object?>{'value': formatNumber(consumption)}) : '';
    return t('orderForm.fuelBasis', <String, Object?>{'price': formatMoney(price), 'date': day, 'per': per});
  }

  Widget _figureRow(String title, String value, {String? subtitle}) {
    return IosRow(
      title: title,
      subtitle: subtitle,
      chevron: false,
      trailing: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text)),
    );
  }

  // Tuyến và chi phí tham khảo, như mục 3 của web: để người báo giá biết mà ghi giá
  Widget _routeGroup() {
    final RouteEstimate? estimate = route;
    final bool canPickVehicle = session?.can('Vehicles.View') ?? false;
    final bool noRoute = estimate != null && estimate.distanceKm <= 0;
    final List<Widget> notes = <Widget>[
      if (routeError != null) Text(routeError!, style: TextStyle(fontSize: 13, height: 1.35, color: IosColors.red)),
      if (form.routeRequest() == null) Text(t('orderForm.routeHint'), style: TextStyle(fontSize: 13, height: 1.35, color: IosColors.secondaryLabel)),
      if (estimate?.warning != null) Text(estimate!.warning!, style: TextStyle(fontSize: 13, height: 1.35, color: AppColors.warnText)),
      if (estimate != null && estimate.tollClassAssumed) Text(t('orderForm.tollAssumedVehicle'), style: TextStyle(fontSize: 13, height: 1.35, color: AppColors.warnText)),
      if (estimate?.fuelWarning != null) Text(estimate!.fuelWarning!, style: TextStyle(fontSize: 13, height: 1.35, color: AppColors.warnText)),
      if (estimate != null && estimate.expressways.isNotEmpty)
        Text(t('orderForm.expressways', <String, Object?>{'names': estimate.expressways.join(', ')}), style: TextStyle(fontSize: 13, height: 1.35, color: IosColors.secondaryLabel)),
      if (estimate != null) Text(t('orderForm.referenceNote'), style: TextStyle(fontSize: 13, height: 1.35, color: IosColors.secondaryLabel)),
      Text(isEditing ? t('orderForm.estimationNoteEdit') : t('orderForm.estimationNote'), style: TextStyle(fontSize: 13, height: 1.35, color: IosColors.secondaryLabel)),
    ];
    return IosGroup(
      header: t('orderForm.routeSection'),
      headerIcon: CupertinoIcons.map_fill,
      footerWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 5,
        children: notes,
      ),
      children: <Widget>[
        if (canPickVehicle)
          IosRow(title: t('orderForm.estimationVehicle'), subtitle: form.estimationVehicleLabel ?? t('orderForm.estimationNone'), onTap: pickEstimationVehicle),
        if (canPickVehicle && form.estimationIsTrailer)
          IosRow(title: t('orderForm.estimationTractor'), subtitle: form.estimationTractorLabel ?? t('orderForm.estimationTractorNone'), onTap: pickEstimationTractor),
        if (routeLoading)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 8,
              children: <Widget>[
                const CupertinoActivityIndicator(),
                Text(t('orderForm.routeCalculating'), style: TextStyle(fontSize: 15, color: IosColors.secondaryLabel)),
              ],
            ),
          )
        else if (estimate != null) ...<Widget>[
          _figureRow(t('orderDetail.distance'), noRoute ? t('orderForm.routeNotComputed') : '${formatNumber(num.parse(estimate.distanceKm.toStringAsFixed(1)))} km'),
          if (estimate.durationMinutes != null && !noRoute) _figureRow(t('orderForm.duration'), routeDurationText(estimate.durationMinutes!)),
          // Web ẩn số này lúc tạo đơn vì chỉ tính một chiều cho một xe dự kiến. App vẫn hiện để người báo giá có số tham khảo,
          // ghi rõ là một chiều; tiền dầu thật theo từng chuyến, từng xe xem ở bước điều phối
          if (estimate.estimatedFuelCost != null && !noRoute)
            _figureRow(t('orderForm.fuelEstimate'), formatMoney(estimate.estimatedFuelCost!), subtitle: fuelBasisText(estimate)),
          _figureRow(
            t('orderDetail.tollCost'),
            formatMoney(estimate.tollCost),
            subtitle: estimate.tollVehicleClass == null ? null : t('orderForm.tollClass', <String, Object?>{'class': estimate.tollVehicleClass}),
          ),
        ],
        if (form.routeRequest() != null && !routeLoading)
          IosRow(icon: CupertinoIcons.arrow_clockwise, iconColor: IosColors.blue, title: t('orderForm.recalcRoute'), chevron: false, onTap: recalculateRoute),
      ],
    );
  }

  Widget _reasonGroup() {
    final bool missing = triedReason && editReason.text.trim().isEmpty;
    return IosGroup(
      header: isEditRequest ? t('orderForm.editReasonLabel') : t('orderForm.repriceReasonLabel'),
      headerIcon: CupertinoIcons.text_bubble_fill,
      footerWidget: missing ? _errorFooter(isEditRequest ? t('orderForm.editReasonRequired') : t('orderForm.repriceReasonRequired')) : null,
      children: <Widget>[
        CupertinoTextField(
          controller: editReason,
          placeholder: isEditRequest ? t('orderForm.editReasonHint') : t('orderForm.repriceReasonHint'),
          placeholderStyle: TextStyle(fontSize: 17, color: IosColors.tertiaryLabel),
          style: TextStyle(fontSize: 17, color: AppColors.text),
          decoration: null,
          padding: const EdgeInsets.all(16),
          minLines: 2,
          maxLines: 5,
          onChanged: (String _) => setState(() {}),
        ),
      ],
    );
  }

  Widget _workDaysGroup(Map<String, String> errorMap) {
    final String? error = errorMap['days'];
    return IosGroup(
      header: t('orderDetail.workDays'),
      headerIcon: CupertinoIcons.calendar,
      footerWidget: error != null
          ? _errorFooter(error)
          : Text(t('orderForm.workDaysNote'), style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel, height: 1.35)),
      children: <Widget>[
        for (int index = 0; index < form.workDays.length; index++)
          IosRow(
            title: form.workDays[index].workDate.isEmpty ? t('orderForm.errorDate') : formatDate(form.workDays[index].workDate),
            subtitle: errorMap['day.${form.workDays[index].key}'] ?? (form.workDays[index].note.isEmpty ? null : form.workDays[index].note),
            value: '${form.workDays[index].startTime} – ${form.workDays[index].endTime}',
            onTap: () => editWorkDay(index),
          ),
        IosRow(icon: CupertinoIcons.add, iconColor: IosColors.green, title: t('orderForm.addWorkDay'), onTap: () => editWorkDay(null)),
      ],
    );
  }

  Widget _cargosGroup(Map<String, String> errorMap) {
    final String? error = errorMap['cargos'];
    final String summary = form.cargos.isEmpty
        ? t('orderForm.cargos')
        : t('orderForm.cargosSummary', <String, Object?>{'count': form.totalPieces, 'weight': formatNumber(form.totalKg)});
    return IosGroup(
      header: summary,
      headerIcon: CupertinoIcons.cube_box_fill,
      footerWidget: error != null
          ? _errorFooter(error)
          : (cargoLocked ? Text(t('orderForm.cargoLocked'), style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel, height: 1.35)) : null),
      children: <Widget>[
        for (int index = 0; index < form.cargos.length; index++)
          _CargoDraftRow(cargo: form.cargos[index], error: errorMap['cargo.${form.cargos[index].key}'], onTap: cargoLocked ? null : () => editCargo(index)),
        if (!cargoLocked) IosRow(icon: CupertinoIcons.add, iconColor: IosColors.green, title: t('orderForm.addCargo'), onTap: () => editCargo(null)),
        if (!cargoLocked) ValueListenableBuilder<bool>(
          valueListenable: orderAiDisabled,
          builder: (BuildContext context, bool disabled, Widget? child) =>
              disabled ? const SizedBox.shrink() : IosRow(leading: const AiOrb(size: 30), title: t('orderForm.readFromImage'), titleWidget: AiBrandText(t('orderForm.readFromImage')), onTap: readWithAi),
        ),
        if (form.cargos.isNotEmpty && (session?.can('Packing.View') ?? false))
          IosRow(
            icon: CupertinoIcons.cube_box_fill,
            iconColor: AppColors.orange,
            title: t('orderForm.plan3d'),
            subtitle: isEditing ? null : t('orderForm.plan3dNote'),
            onTap: busy != null ? null : openPacking,
          ),
      ],
    );
  }

  // Xe ước tính (loại, tải trọng) để gợi ý giá; đang sửa đơn thì chỉ có id nên tải lại xe
  Vehicle? get estimationVehicle {
    final String? id = form.estimationVehicleId;
    if (id == null || !(session?.can('Vehicles.View') ?? false)) return null;
    final Vehicle? loaded = ref.watch(vehicleProvider(id)).value?.summary;
    return loaded ?? (pickedVehicle?.publicId == id ? pickedVehicle : null);
  }

  /// Câu nói đúng điều kiện còn thiếu để có giá gợi ý. null: không cần nhắc (không có quyền xem xe, đang tải xe).
  String? priceSuggestionHint(Vehicle? vehicle, PriceClass? priceClass) {
    if (!(session?.can('Vehicles.View') ?? false)) return null;
    if (form.estimationVehicleId == null) return t('orderForm.suggestedPriceNeedVehicle');
    if (vehicle == null) return null;
    if (priceClass == null) return t('orderForm.suggestedPriceNoRate');
    if (form.stops.length < 2) return t('orderForm.suggestedPriceNeedStops');
    for (int index = 0; index < form.stops.length; index++) {
      final StopDraft stop = form.stops[index];
      if (!stop.hasCoordinates) {
        return t('orderForm.suggestedPriceNeedPin', <String, Object?>{'number': index + 1, 'kind': tEnum('stopKind', stop.kind).toLowerCase()});
      }
    }
    if (routeLoading) return t('orderForm.suggestedPriceRouting');
    return t('orderForm.suggestedPriceNoRoute');
  }

  String millions(int amount) => millionsText(amount, I18n.lang == 'en' ? '.' : ',');

  String suggestionBasis(PriceSuggestion suggestion, num distanceKm) {
    final (int low, int high) = pricePerKm[suggestion.priceClass]!;
    return t('orderForm.suggestedPriceBasis', <String, Object?>{
          'class': t('priceClass.${suggestion.priceClass.name}'),
          'low': formatNumber(low ~/ 1000),
          'high': formatNumber(high ~/ 1000),
          'km': formatNumber(distanceKm.round()),
        }) +
        (suggestion.oversize ? t('orderForm.suggestedPriceOversize') : '') +
        (suggestion.minimum ? t('orderForm.suggestedPriceMinimum') : '');
  }

  Widget _priceGroup(Map<String, String> errorMap) {
    final String? error = errorMap['quoted'];
    // Đang tính lại tuyến thì giữ số km lần trước: thẻ không tắt rồi hiện lại, chỉ cuộn số sang giá mới
    final RouteEstimate? estimate = routeLoading ? lastRoute : route;
    final num distance = estimate?.distanceKm ?? 0;
    final Vehicle? vehicle = estimationVehicle;
    final PriceClass? priceClass = vehicle == null ? null : priceClassFor(vehicle.baseType, vehicle.maxPayloadKg);
    final PriceSuggestion? suggestion =
        priceClass == null ? null : suggestPrice(priceClass, distance, oversize: cargoIsOversize(form, vehicle?.maxPayloadKg));
    final int quotedValue = parseMoneyInput(quoted.text) ?? 0;
    final num cost = (estimate?.estimatedFuelCost ?? 0) + (estimate?.tollCost ?? 0);
    final num kg = form.totalKg;
    final TextStyle note = TextStyle(fontSize: 13, height: 1.35, color: IosColors.secondaryLabel);
    // Chưa có giá: nói rõ thiếu gì ngay chỗ thẻ giá sẽ hiện, không giấu trong chú thích nhỏ
    final String? hint = suggestion == null ? priceSuggestionHint(vehicle, priceClass) : null;
    final List<Widget> footer = <Widget>[
      if (error != null) _errorFooter(error),
      if (suggestion != null) Text(t('orderForm.suggestedPriceNote'), style: note),
      if (quotedValue > 0 && quotedValue < cost) _errorFooter(t('orderForm.quoteBelowCost', <String, Object?>{'amount': formatMoney(cost)})),
      if (distance >= marketReferenceMinKm && kg > 0)
        Text(
          t('orderForm.marketReference', <String, Object?>{'tons': formatNumber(num.parse((kg / 1000).toStringAsFixed(1))), 'amount': formatMoney(marketReferencePrice(kg))}),
          style: note,
        ),
    ];
    final Widget group = IosGroup(
      header: t('orderDetail.quote'),
      headerIcon: CupertinoIcons.tag_fill,
      footerWidget: footer.isEmpty ? null : Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 5, children: footer),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: <Widget>[
              Expanded(child: Text(t('orderForm.quotedAmount'), style: TextStyle(fontSize: 17, color: AppColors.text))),
              Expanded(
                child: CupertinoTextField(
                  controller: quoted,
                  textAlign: TextAlign.right,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[MoneyInputFormatter()],
                  placeholder: '0 đ',
                  placeholderStyle: TextStyle(fontSize: 17, color: IosColors.tertiaryLabel),
                  style: TextStyle(fontSize: 17, color: AppColors.text),
                  decoration: null,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  onChanged: (String _) => setState(() {}),
                ),
              ),
            ],
          ),
        ),
        IosRow(title: t('orderForm.profile'), subtitle: tEnum('operatingProfile', form.operatingProfile), onTap: pickProfile),
        CupertinoTextField(
          controller: notes,
          placeholder: t('orderForm.notes'),
          placeholderStyle: TextStyle(fontSize: 17, color: IosColors.tertiaryLabel),
          style: TextStyle(fontSize: 17, color: AppColors.text),
          decoration: null,
          padding: const EdgeInsets.all(16),
          minLines: 2,
          maxLines: 5,
          onChanged: (String _) => setState(() {}),
        ),
      ],
    );
    // Thẻ giá gợi ý kiểu LiftMate Intelligence nằm ngay trên ô giá báo, hiện ra khi đủ xe và tuyến
    return Column(
      children: <Widget>[
        AnimatedSize(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          clipBehavior: Clip.none,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: suggestion == null
                ? (hint == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        key: const ValueKey<String>('priceHint'),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        child: _PriceHintCard(title: t('orderForm.suggestedPrice'), text: hint, busy: routeLoading),
                      ))
                // Khóa cố định: đổi tuyến, đổi xe thì giữ thẻ, chỉ cuộn số sang giá mới
                : Padding(
                    key: const ValueKey<String>('priceSuggestion'),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    child: _PriceSuggestionCard(
                      title: t('orderForm.suggestedPrice'),
                      low: suggestion.low,
                      high: suggestion.high,
                      rangeText: (int low, int high) => t('orderForm.priceRangeMillions', <String, Object?>{'low': millions(low), 'high': millions(high)}),
                      basis: suggestionBasis(suggestion, distance),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => quoted.text = formatNumber(suggestion.middle));
                      },
                    ),
                  ),
          ),
        ),
        group,
      ],
    );
  }
}

/// Chỗ của thẻ giá gợi ý khi chưa có giá: thẻ nhạt nói còn thiếu gì (chọn xe, chọn địa chỉ, loại xe chưa có đơn giá)
class _PriceHintCard extends StatelessWidget {
  final String title;
  final String text;
  final bool busy;

  const _PriceHintCard({required this.title, required this.text, required this.busy});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(_PriceSuggestionCard.radius),
        border: Border.all(color: IosColors.separator),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: <Widget>[
          SizedBox(
            width: 30,
            height: 30,
            child: busy
                ? const CupertinoActivityIndicator()
                : Icon(CupertinoIcons.sparkles, size: 24, color: IosColors.secondaryLabel),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: <Widget>[
                Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
                Text(text, style: TextStyle(fontSize: 14, height: 1.35, color: IosColors.secondaryLabel)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Giá gợi ý: viền quầng màu, quả cầu và chữ dải màu như các ô LiftMate Intelligence; bấm để điền giá giữa.
/// Như thông báo ưu tiên của Apple Intelligence: thẻ hiện ra trước (nở từ nhỏ, mờ sang rõ), hiện xong thì viền màu
/// lóe sáng chạy một vòng quanh mép rồi lắng thành quầng màu thường trực. Giá cuộn số từ 0, đổi tuyến thì cuộn sang giá mới.
class _PriceSuggestionCard extends StatefulWidget {
  static const double radius = 24;

  final String title;
  final int low;
  final int high;
  final String Function(int low, int high) rangeText;
  final String basis;
  final VoidCallback onTap;

  const _PriceSuggestionCard({required this.title, required this.low, required this.high, required this.rangeText, required this.basis, required this.onTap});

  @override
  State<_PriceSuggestionCard> createState() => _PriceSuggestionCardState();
}

class _PriceSuggestionCardState extends State<_PriceSuggestionCard> with SingleTickerProviderStateMixin {
  late final AnimationController enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  ScrollPosition? position;

  // Thẻ được dựng sẵn ngoài màn hình (vùng đệm của danh sách) nên chỉ chạy hiệu ứng khi thẻ lọt vào màn hình
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      enter.value = 1;
      return;
    }
    if (!enter.isDismissed) return;
    position?.removeListener(startWhenVisible);
    position = Scrollable.maybeOf(context)?.position;
    position?.addListener(startWhenVisible);
    WidgetsBinding.instance.addPostFrameCallback((Duration _) => startWhenVisible());
  }

  void startWhenVisible() {
    if (!mounted || !enter.isDismissed) return;
    final RenderObject? box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final double top = box.localToGlobal(Offset.zero).dy;
    // Trừ thanh nút Lưu ở đáy màn hình: thấy được quá nửa thẻ thì bắt đầu
    final double visibleBottom = MediaQuery.sizeOf(context).height - 100;
    if (top + box.size.height * 0.5 < visibleBottom && top + box.size.height > 0) {
      position?.removeListener(startWhenVisible);
      enter.forward();
    }
  }

  @override
  void dispose() {
    position?.removeListener(startWhenVisible);
    enter.dispose();
    super.dispose();
  }

  // Lần đầu số cuộn từ 0 cùng lúc thẻ hiện ra; đổi tuyến, đổi xe thì cuộn từ giá cũ sang giá mới. Bước 100 nghìn cho khớp cách làm tròn
  Widget rollingRange() {
    Widget roll(int value, Widget Function(double shown) builder) => TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: value.toDouble(), end: value.toDouble()),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (BuildContext context, double shown, Widget? child) => builder(shown),
        );
    return AnimatedBuilder(
      animation: enter,
      builder: (BuildContext context, Widget? child) {
        final double grow = Curves.easeOutCubic.transform(((enter.value - appearEnd * 0.4) / 0.55).clamp(0.0, 1.0));
        return roll(widget.low, (double low) => roll(widget.high, (double high) {
              return AiGradient(
                child: Text(
                  widget.rangeText(roundPrice(low * grow), roundPrice(high * grow)),
                  style: aiTextStyle(22, fontWeight: FontWeight.w700).copyWith(fontFeatures: const <FontFeature>[FontFeature.tabularFigures()]),
                ),
              );
            }));
      },
    );
  }

  // Mốc trên dòng thời gian của [enter]: 0 → appearEnd thẻ hiện ra, sau đó lóe viền
  static const double appearEnd = 0.3;

  Widget content(double glow) {
    return AiGlow(
      radius: _PriceSuggestionCard.radius,
      strength: glow,
      child: DecoratedBox(
        decoration: aiFieldDecoration(radius: _PriceSuggestionCard.radius),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 18, 14),
          child: Row(
            children: <Widget>[
              const AiOrb(size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: <Widget>[
                    AiGradient(child: Text(widget.title, style: aiTextStyle(17, fontWeight: FontWeight.w600))),
                    Text(widget.basis, style: TextStyle(fontSize: 13, height: 1.3, color: IosColors.secondaryLabel)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              rollingRange(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${widget.title} ${widget.rangeText(widget.low, widget.high)}',
      child: AiPressEffect(
        pressedScale: 1.03,
        radius: _PriceSuggestionCard.radius,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedBuilder(
            animation: enter,
            builder: (BuildContext context, Widget? child) {
              final double value = enter.value;
              if (value == 1) return content(1);
              // Bước 1: nở ra có nảy nhẹ, mờ nhòe sang rõ, chưa có quầng
              final double shown = (value / appearEnd).clamp(0.0, 1.0);
              final double grow = Curves.easeOutBack.transform(shown);
              final double appear = Curves.easeOut.transform(shown);
              final double blur = 10 * (1 - appear);
              // Bước 2: lóe sáng lên nhanh rồi tắt chậm, vệt màu chạy một vòng quanh mép; quầng thường trực hiện dần
              final double lit = ((value - appearEnd) / (1 - appearEnd)).clamp(0.0, 1.0);
              final double flash = lit < 0.2 ? Curves.easeOut.transform(lit / 0.2) : 1 - Curves.easeInOut.transform((lit - 0.2) / 0.8);
              final double pop = 1 + 0.018 * math.sin(math.pi * math.min(1, lit / 0.4));
              Widget result = Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  content(Curves.easeIn.transform(lit)),
                  if (flash > 0.01)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(painter: _FlashRingPainter(radius: _PriceSuggestionCard.radius, turn: Curves.easeOutCubic.transform(lit), intensity: flash)),
                      ),
                    ),
                ],
              );
              if (blur > 0.1) result = ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: result);
              return Opacity(
                opacity: appear,
                child: Transform.scale(scale: (0.86 + 0.14 * grow) * pop, child: result),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Viền màu lóe sáng quanh mép thẻ: quầng nhòe to bên ngoài và nét sáng mảnh sát mép, dải màu xoay theo [turn] (0 → 1 là một vòng)
class _FlashRingPainter extends CustomPainter {
  final double radius;
  final double turn;
  final double intensity;

  const _FlashRingPainter({required this.radius, required this.turn, required this.intensity});

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final RRect edge = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final Shader shader = aiSweepGradient(turn * 9).createShader(rect.inflate(8));
    canvas.drawRRect(
      edge.inflate(3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..shader = shader
        ..color = Colors.black.withValues(alpha: 0.9 * intensity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawRRect(
      edge.deflate(0.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..shader = shader
        ..color = Colors.black.withValues(alpha: intensity),
    );
  }

  @override
  bool shouldRepaint(_FlashRingPainter oldDelegate) => oldDelegate.turn != turn || oldDelegate.intensity != intensity || oldDelegate.radius != radius;
}

class _StopDraftRow extends StatelessWidget {
  final StopDraft stop;
  final int number;
  final int dragIndex;
  final String? error;
  final VoidCallback onTap;

  const _StopDraftRow({required this.stop, required this.number, required this.dragIndex, required this.error, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final String contact = stop.kind == 'Via' ? '' : <String>[stop.contactName.trim(), stop.contactPhone.trim()].where((String part) => part.isNotEmpty).join(' · ');
    return CupertinoButton(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
      alignment: Alignment.centerLeft,
      onPressed: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: stopColor(stop.kind), shape: BoxShape.circle),
            child: Text('$number', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  stop.kind == 'Delivery' ? '${label(stopKindLabels, stop.kind)} · ${stop.unloadMethod == 'Crane' ? t('orderForm.unloadCrane') : t('orderForm.unloadForklift')}' : label(stopKindLabels, stop.kind),
                  style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel),
                ),
                Text(
                  stop.address.trim().isEmpty ? t('orderForm.addressEmpty') : stop.address,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                    color: stop.address.trim().isEmpty ? IosColors.tertiaryLabel : AppColors.text,
                  ),
                ),
                if (contact.isNotEmpty) Text(contact, style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel, height: 1.4)),
                if (stop.address.trim().isNotEmpty && !stop.hasCoordinates)
                  Text(t('orderForm.addressNoCoordinatesShort'), style: TextStyle(fontSize: 13, color: AppColors.warnText, height: 1.4)),
                if (error != null) Text(error!, style: TextStyle(fontSize: 13, color: IosColors.red, height: 1.4)),
              ],
            ),
          ),
          // Kéo ở đây là đi ngay; giữ ở chỗ khác trên dòng thì đợi một nhịp để không vướng cuộn trang
          ReorderableDragStartListener(
            index: dragIndex,
            child: Semantics(
              label: t('orderForm.dragToReorder'),
              child: SizedBox(
                width: 44,
                height: 40,
                child: Icon(CupertinoIcons.line_horizontal_3, size: 22, color: IosColors.tertiaryLabel),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CargoDraftRow extends StatelessWidget {
  final CargoDraft cargo;
  final String? error;
  final VoidCallback? onTap;

  const _CargoDraftRow({required this.cargo, required this.error, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final String size = <String>[cargo.lengthMm, cargo.widthMm, cargo.heightMm].map((String v) => v.isEmpty ? '?' : v).join(' × ');
    final String weight = cargo.weightKg.isEmpty ? '?' : cargo.weightKg;
    return CupertinoButton(
      padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
      alignment: Alignment.centerLeft,
      onPressed: onTap,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${cargo.cargoName.isEmpty ? t('orderForm.cargoNoName') : cargo.cargoName} × ${cargo.quantity.isEmpty ? '?' : cargo.quantity}',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.3),
                ),
                Text(t('orderForm.cargoLine', <String, Object?>{'weight': weight, 'size': size}), style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel, height: 1.4)),
                if (error != null) Text(error!, style: TextStyle(fontSize: 13, color: IosColors.red, height: 1.4)),
              ],
            ),
          ),
          if (onTap != null) Icon(CupertinoIcons.chevron_forward, size: 18, color: IosColors.tertiaryLabel),
        ],
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  final String? busy;
  final String draftLabel;
  // null: không có nút báo giá, chỉ một nút lưu
  final String? quoteLabel;
  final VoidCallback onDraft;
  final VoidCallback onQuote;

  const _SaveBar({required this.busy, required this.draftLabel, required this.quoteLabel, required this.onDraft, required this.onQuote});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.paddingOf(context).bottom + 10),
      child: Glass(
        borderRadius: BorderRadius.circular(32),
        opacity: 0.85,
        padding: const EdgeInsets.all(8),
        child: quoteLabel == null
            ? SizedBox(height: 50, child: IosPillButton(label: draftLabel, busy: busy == 'draft', onPressed: busy == null ? onDraft : null))
            : Row(
          children: <Widget>[
            Expanded(
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: busy == null ? onDraft : null,
                child: Container(
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.fillSoft, borderRadius: BorderRadius.circular(999)),
                  child: busy == 'draft'
                      ? const CupertinoActivityIndicator()
                      : Text(draftLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: IosColors.blue)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 50,
                child: IosPillButton(label: quoteLabel!, busy: busy == 'quote', onPressed: busy == null ? onQuote : null),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
