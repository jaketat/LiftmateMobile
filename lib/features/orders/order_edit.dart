// Sửa đơn đã lưu, theo đúng luật của web (status.ts, EditOrderPage, CargoTab).
// Server tách làm nhiều lệnh (đơn, ngày làm, từng kiện) nên chỉ gửi phần thật sự đổi: sửa giá không phải tính lại tuyến.
// Một lệnh lỗi thì dừng, phần đã xong được ghi nhận để bấm lại không gửi lặp.
import 'dart:convert';

import '../../core/session.dart';
import '../driver/account_api.dart' show newIdempotencyKey;
import 'order_form.dart';
import 'orders_api.dart';

const List<String> _lockedStatuses = <String>['Invoiced', 'Cancelled'];
const List<String> _requestableStatuses = <String>['CustomerConfirmed', 'Scheduled', 'InProgress', 'AwaitingFinalization'];

/// Sửa đơn, điểm dừng, kiện: Nháp, Đã báo giá với Orders.Edit (BR-ORD-006);
/// có thêm Orders.EditAnyStage thì mọi bước trừ Đã xuất hóa đơn, Đã hủy (BR-ORD-076)
bool canEditOrder(String status, Session? session) {
  if (session == null || !session.can('Orders.Edit')) return false;
  return status == 'Draft' || status == 'Quoted' || (session.can('Orders.EditAnyStage') && !_lockedStatuses.contains(status));
}

/// Ngày làm: tới Đã chốt lịch (BR-ORD-022), có Orders.EditAnyStage thì như sửa đơn
bool canEditWorkDays(String status, Session? session) {
  if (session == null || !session.can('Orders.Edit')) return false;
  return const <String>['Draft', 'Quoted', 'CustomerConfirmed', 'Scheduled'].contains(status) || (session.can('Orders.EditAnyStage') && !_lockedStatuses.contains(status));
}

/// Bước đã khóa nhưng gửi được đề nghị sửa cho giám đốc duyệt (BR-ORD-079)
bool mustRequestEdit(String status, Session? session) {
  return session != null && session.can('Orders.Edit') && !canEditOrder(status, session) && _requestableStatuses.contains(status);
}

bool mustRequestWorkDays(String status, Session? session) {
  return session != null && session.can('Orders.Edit') && !canEditWorkDays(status, session) && _requestableStatuses.contains(status);
}

/// Thân lệnh PUT /orders/{id}. Server coi trường bỏ trống là xóa nên phải gửi đủ
Map<String, dynamic> orderUpdateBody(OrderFormData form) {
  return <String, dynamic>{
    'stops': <Map<String, dynamic>>[for (final StopDraft stop in form.stops) stop.toJson()],
    'operatingProfile': form.operatingProfile,
    'quotedAmount': form.quotedAmount,
    'notes': form.notes.trim().isEmpty ? null : form.notes.trim(),
    'estimationVehiclePublicId': form.estimationVehicleId,
    'estimationTractorPublicId': form.estimationTractorId,
  };
}

List<Map<String, dynamic>> orderWorkDaysBody(OrderFormData form) {
  return <Map<String, dynamic>>[for (final WorkDayDraft day in form.workDays) day.toJson()];
}

/// Trạng thái đang có trên server, để so với form
class OrderEditBaseline {
  String orderBody;
  String workDaysBody;
  // Mã kiện → nội dung các ô sửa được
  final Map<String, String> cargos;
  // Giữ nguyên qua các lần bấm lại: thêm kiện không bị trùng
  String addCargosKey = newIdempotencyKey();

  OrderEditBaseline._(this.orderBody, this.workDaysBody, this.cargos);

  factory OrderEditBaseline.of(OrderFormData form) {
    return OrderEditBaseline._(
      jsonEncode(orderUpdateBody(form)),
      jsonEncode(orderWorkDaysBody(form)),
      <String, String>{
        for (final CargoDraft cargo in form.cargos)
          if (cargo.serverId != null) cargo.serverId!: jsonEncode(cargo.editableJson()),
      },
    );
  }
}

/// Phần cần gửi lên server
class OrderEditChanges {
  final bool order;
  final bool workDays;
  final List<String> removedCargos;
  final List<CargoDraft> changedCargos;
  final List<CargoDraft> newCargos;

  const OrderEditChanges({required this.order, required this.workDays, required this.removedCargos, required this.changedCargos, required this.newCargos});

  bool get isEmpty => !order && !workDays && removedCargos.isEmpty && changedCargos.isEmpty && newCargos.isEmpty;
}

OrderEditChanges orderEditChanges(OrderFormData form, OrderEditBaseline baseline) {
  final Set<String> kept = <String>{
    for (final CargoDraft cargo in form.cargos)
      if (cargo.serverId != null) cargo.serverId!,
  };
  return OrderEditChanges(
    order: jsonEncode(orderUpdateBody(form)) != baseline.orderBody,
    workDays: jsonEncode(orderWorkDaysBody(form)) != baseline.workDaysBody,
    removedCargos: <String>[
      for (final String id in baseline.cargos.keys)
        if (!kept.contains(id)) id,
    ],
    changedCargos: <CargoDraft>[
      for (final CargoDraft cargo in form.cargos)
        if (cargo.serverId != null && jsonEncode(cargo.editableJson()) != baseline.cargos[cargo.serverId]) cargo,
    ],
    newCargos: <CargoDraft>[
      for (final CargoDraft cargo in form.cargos)
        if (cargo.serverId == null) cargo,
    ],
  );
}

/// Có phần nào phải chờ giám đốc duyệt không, ứng với thay đổi hiện tại
bool editNeedsApproval(OrderEditChanges changes, String status, Session? session) {
  return (changes.order && mustRequestEdit(status, session)) || (changes.workDays && mustRequestWorkDays(status, session));
}

/// Ghi thay đổi. [reason]: lý do đề nghị sửa, hoặc lý do đổi giá đơn Đã chốt. Trả true nếu có phần chờ duyệt
Future<bool> saveOrderEdits(OrderFormData form, OrderDetail order, OrderEditBaseline baseline, {required Session? session, String? reason}) async {
  final OrderEditChanges changes = orderEditChanges(form, baseline);
  final String id = order.publicId;
  final String? trimmed = reason == null || reason.trim().isEmpty ? null : reason.trim();
  bool requested = false;
  if (changes.order) {
    final Map<String, dynamic> body = orderUpdateBody(form);
    if (mustRequestEdit(order.status, session)) {
      await createOrderEditRequest(id, <String, dynamic>{'kind': 'OrderInfo', 'orderInfo': body, 'reason': trimmed});
      requested = true;
    } else {
      await updateOrder(id, <String, dynamic>{...body, 'editReason': trimmed});
    }
    baseline.orderBody = jsonEncode(body);
  }
  if (changes.workDays) {
    final List<Map<String, dynamic>> body = orderWorkDaysBody(form);
    if (mustRequestWorkDays(order.status, session)) {
      await createOrderEditRequest(id, <String, dynamic>{'kind': 'WorkDays', 'workDays': body, 'reason': trimmed});
      requested = true;
    } else {
      await replaceOrderWorkDays(id, body);
    }
    baseline.workDaysBody = jsonEncode(body);
  }
  // Như web: thêm, sửa rồi mới xóa. Kiện không có đường đề nghị sửa nên form đã khóa phần này khi đơn bị khóa
  if (canEditOrder(order.status, session)) {
    if (changes.newCargos.isNotEmpty) {
      await addOrderCargos(id, <Map<String, dynamic>>[for (final CargoDraft cargo in changes.newCargos) cargo.toJson()], idempotencyKey: baseline.addCargosKey);
    }
    for (final CargoDraft cargo in changes.changedCargos) {
      await updateOrderCargo(id, cargo.serverId!, cargo.toUpdateJson());
      baseline.cargos[cargo.serverId!] = jsonEncode(cargo.editableJson());
    }
    for (final String cargoId in changes.removedCargos) {
      await deleteOrderCargo(id, cargoId);
      baseline.cargos.remove(cargoId);
    }
  }
  return requested;
}
