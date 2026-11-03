// Dữ liệu và luật kiểm tra của form tạo đơn, không dính giao diện. Luật theo backend và web (slice-03 mục 2.3).
import '../../core/i18n.dart';
import 'orders_api.dart';

const int maxOrderStops = 20;
const int maxAiTextChars = 8000;
const int maxAiImageBytes = 10 * 1024 * 1024;

int _nextKey = 0;
String _newKey() => 'k${++_nextKey}';

/// Đọc số người dùng gõ. Kg, mm là số nguyên: "25.000" có thể là 25 hay 25000 nên từ chối, bắt gõ liền.
/// Số lẻ nhận cả "12,5" lẫn "12.5". Trả null nếu ô trống, NaN nếu không hợp lệ.
num? parseNumberInput(String text, {required bool integer}) {
  final String value = text.replaceAll(RegExp(r'\s'), '');
  if (value.isEmpty) return null;
  if (integer) return RegExp(r'^-?\d+$').hasMatch(value) ? int.parse(value) : double.nan;
  return RegExp(r'^-?\d+([.,]\d+)?$').hasMatch(value) ? double.parse(value.replaceAll(',', '.')) : double.nan;
}

/// Số khách, số liên hệ: di động 10 số đầu 03, 05, 07, 08, 09, hoặc số bàn 11 số đầu 02. Cho phép +84 và dấu ngăn cách.
bool isValidCustomerPhone(String phone) {
  String value = phone.trim().replaceAll(RegExp(r'[\s.\-()]'), '');
  if (value.startsWith('+84')) {
    value = '0${value.substring(3)}';
  } else if (value.startsWith('84') && (value.length == 11 || value.length == 12)) {
    value = '0${value.substring(2)}';
  }
  return RegExp(r'^0[35789]\d{8}$').hasMatch(value) || RegExp(r'^02\d{9}$').hasMatch(value);
}

class StopDraft {
  final String key;
  // Pickup, Delivery, Via
  String kind;
  String address;
  double? latitude;
  double? longitude;
  String contactName;
  String contactPhone;
  String note;
  // Crane, ForkliftFromRear. Chỉ điểm trả mới gửi
  String unloadMethod;

  StopDraft({
    required this.kind,
    String? key,
    this.address = '',
    this.latitude,
    this.longitude,
    this.contactName = '',
    this.contactPhone = '',
    this.note = '',
    this.unloadMethod = 'Crane',
  }) : key = key ?? _newKey();

  StopDraft copy() => StopDraft(
        key: key,
        kind: kind,
        address: address,
        latitude: latitude,
        longitude: longitude,
        contactName: contactName,
        contactPhone: contactPhone,
        note: note,
        unloadMethod: unloadMethod,
      );

  bool get hasCoordinates => latitude != null && longitude != null;

  Map<String, dynamic> toDraft() => <String, dynamic>{
        'kind': kind,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'contactName': contactName,
        'contactPhone': contactPhone,
        'note': note,
        'unloadMethod': unloadMethod,
      };

  factory StopDraft.fromOrder(OrderStop stop) => StopDraft(
        kind: stop.kind,
        address: stop.address,
        latitude: stop.latitude,
        longitude: stop.longitude,
        contactName: stop.contactName ?? '',
        contactPhone: stop.contactPhone ?? '',
        note: stop.note ?? '',
        unloadMethod: stop.unloadMethod ?? 'Crane',
      );

  factory StopDraft.fromDraft(Map<String, dynamic> json) => StopDraft(
        kind: json['kind'] as String,
        address: json['address'] as String,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        contactName: json['contactName'] as String,
        contactPhone: json['contactPhone'] as String,
        note: json['note'] as String,
        unloadMethod: json['unloadMethod'] as String,
      );

  Map<String, dynamic> toJson() {
    final bool via = kind == 'Via';
    return <String, dynamic>{
      'kind': kind,
      'address': address.trim(),
      'latitude': latitude,
      'longitude': longitude,
      // Đi qua: không bốc trả nên không cần người liên hệ; cách dỡ chỉ cho điểm trả (gửi ở điểm khác là 400)
      'contactName': via || contactName.trim().isEmpty ? null : contactName.trim(),
      'contactPhone': via || contactPhone.trim().isEmpty ? null : contactPhone.trim(),
      'note': note.trim().isEmpty ? null : note.trim(),
      'unloadMethod': kind == 'Delivery' ? unloadMethod : null,
    };
  }
}

class WorkDayDraft {
  final String key;
  // yyyy-MM-dd
  String workDate;
  // HH:mm
  String startTime;
  String endTime;
  String note;

  WorkDayDraft({String? key, this.workDate = '', this.startTime = '08:00', this.endTime = '17:00', this.note = ''}) : key = key ?? _newKey();

  WorkDayDraft copy() => WorkDayDraft(key: key, workDate: workDate, startTime: startTime, endTime: endTime, note: note);

  Map<String, dynamic> toDraft() => <String, dynamic>{'workDate': workDate, 'startTime': startTime, 'endTime': endTime, 'note': note};

  factory WorkDayDraft.fromOrder(OrderWorkDay day) => WorkDayDraft(
        workDate: day.workDate.length >= 10 ? day.workDate.substring(0, 10) : day.workDate,
        startTime: day.startTime.length >= 5 ? day.startTime.substring(0, 5) : day.startTime,
        endTime: day.endTime.length >= 5 ? day.endTime.substring(0, 5) : day.endTime,
        note: day.note ?? '',
      );

  factory WorkDayDraft.fromDraft(Map<String, dynamic> json) => WorkDayDraft(
        workDate: json['workDate'] as String,
        startTime: json['startTime'] as String,
        endTime: json['endTime'] as String,
        note: json['note'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'workDate': workDate,
        'startTime': '$startTime:00',
        'endTime': '$endTime:00',
        'note': note.trim().isEmpty ? null : note.trim(),
      };
}

/// Ô AI đọc chưa chắc: chữ gốc trong tin và lý do. Người dùng phải sửa hoặc bấm "Đúng rồi" mới lưu được (BR-AI-003)
class AiFlag {
  final String? raw;
  final String? reason;

  const AiFlag({this.raw, this.reason});
}

class CargoDraft {
  final String key;
  String cargoName;
  String quantity;
  String weightKg;
  String lengthMm;
  String widthMm;
  String heightMm;
  bool isFragile;
  bool doNotStack;
  bool rotationAllowed;
  bool canLieDown;
  // Flat, Cylinder... Mặc định đế phẳng; AI đọc ra loại khác thì giữ nguyên
  String supportType;
  String saddleHeightMm;
  Map<String, AiFlag> aiFlags;
  // Chữ gốc trong tin của từng ô, để người dùng so số AI đọc
  Map<String, String> aiRaws;
  List<String> issues;
  String? sourceText;
  // Điểm bốc, trả của kiện, theo số thứ tự điểm. Chỉ chọn khi đơn có nhiều điểm bốc hoặc nhiều điểm trả
  int? pickupStopSequence;
  int? dropStopSequence;
  // Thẻ hàng nặng và kế hoạch
  String dimensionsSource;
  String cogSource;
  String cogOffsetXMm;
  String cogOffsetYMm;
  String cogHeightMm;
  String deliveryWave;
  // yyyy-MM-dd; trống là đã sẵn sàng
  String readyDate;
  String travelGroup;
  // Kiện đã có trên server (đang sửa đơn); null là kiện mới
  String? serverId;
  Map<String, dynamic>? serverRaw;

  CargoDraft({
    String? key,
    this.cargoName = '',
    this.quantity = '1',
    this.weightKg = '',
    this.lengthMm = '',
    this.widthMm = '',
    this.heightMm = '',
    this.isFragile = false,
    this.doNotStack = false,
    this.rotationAllowed = true,
    this.canLieDown = false,
    this.supportType = 'Flat',
    this.saddleHeightMm = '',
    Map<String, AiFlag>? aiFlags,
    Map<String, String>? aiRaws,
    List<String>? issues,
    this.sourceText,
    this.pickupStopSequence,
    this.dropStopSequence,
    this.dimensionsSource = 'Estimated',
    this.cogSource = 'Estimated',
    this.cogOffsetXMm = '',
    this.cogOffsetYMm = '',
    this.cogHeightMm = '',
    this.deliveryWave = '1',
    this.readyDate = '',
    this.travelGroup = '',
    this.serverId,
    this.serverRaw,
  })  : key = key ?? _newKey(),
        aiFlags = aiFlags ?? <String, AiFlag>{},
        aiRaws = aiRaws ?? <String, String>{},
        issues = issues ?? <String>[];

  CargoDraft copy() => CargoDraft(
        key: key,
        cargoName: cargoName,
        quantity: quantity,
        weightKg: weightKg,
        lengthMm: lengthMm,
        widthMm: widthMm,
        heightMm: heightMm,
        isFragile: isFragile,
        doNotStack: doNotStack,
        rotationAllowed: rotationAllowed,
        canLieDown: canLieDown,
        supportType: supportType,
        saddleHeightMm: saddleHeightMm,
        aiFlags: Map<String, AiFlag>.of(aiFlags),
        aiRaws: Map<String, String>.of(aiRaws),
        issues: List<String>.of(issues),
        sourceText: sourceText,
        pickupStopSequence: pickupStopSequence,
        dropStopSequence: dropStopSequence,
        dimensionsSource: dimensionsSource,
        cogSource: cogSource,
        cogOffsetXMm: cogOffsetXMm,
        cogOffsetYMm: cogOffsetYMm,
        cogHeightMm: cogHeightMm,
        deliveryWave: deliveryWave,
        readyDate: readyDate,
        travelGroup: travelGroup,
        serverId: serverId,
        serverRaw: serverRaw,
      );

  factory CargoDraft.fromOrder(OrderCargo cargo) {
    final Map<String, dynamic> raw = cargo.raw;
    return CargoDraft(
      cargoName: cargo.cargoName,
      quantity: '${cargo.quantity}',
      weightKg: '${cargo.weightKg}',
      lengthMm: '${cargo.lengthMm}',
      widthMm: '${cargo.widthMm}',
      heightMm: '${cargo.heightMm}',
      isFragile: cargo.isFragile,
      doNotStack: cargo.doNotStack,
      rotationAllowed: (raw['rotationAllowed'] as bool?) ?? true,
      canLieDown: (raw['canLieDown'] as bool?) ?? false,
      supportType: (raw['supportType'] as String?) ?? 'Flat',
      saddleHeightMm: raw['saddleHeightMm'] == null ? '' : '${raw['saddleHeightMm']}',
      pickupStopSequence: (raw['pickupStopSequence'] as num?)?.toInt(),
      dropStopSequence: (raw['dropStopSequence'] as num?)?.toInt(),
      dimensionsSource: (raw['dimensionsSource'] as String?) ?? 'Estimated',
      cogSource: (raw['cogSource'] as String?) ?? 'Estimated',
      cogOffsetXMm: raw['cogOffsetXMm'] == null ? '' : '${raw['cogOffsetXMm']}',
      cogOffsetYMm: raw['cogOffsetYMm'] == null ? '' : '${raw['cogOffsetYMm']}',
      cogHeightMm: raw['cogHeightMm'] == null ? '' : '${raw['cogHeightMm']}',
      deliveryWave: raw['deliveryWave'] == null ? '1' : '${raw['deliveryWave']}',
      readyDate: raw['readyDate'] is String && (raw['readyDate'] as String).length >= 10 ? (raw['readyDate'] as String).substring(0, 10) : '',
      travelGroup: (raw['travelGroup'] as String?) ?? '',
      serverId: cargo.publicId,
      serverRaw: raw,
    );
  }

  // Kiện từ AI chỉ vào form sau khi đã hết ô đỏ, nên không cần giữ dấu của AI
  Map<String, dynamic> toDraft() => <String, dynamic>{
        'cargoName': cargoName,
        'quantity': quantity,
        'weightKg': weightKg,
        'lengthMm': lengthMm,
        'widthMm': widthMm,
        'heightMm': heightMm,
        'isFragile': isFragile,
        'doNotStack': doNotStack,
        'rotationAllowed': rotationAllowed,
        'canLieDown': canLieDown,
        'supportType': supportType,
        'saddleHeightMm': saddleHeightMm,
        'pickupStopSequence': pickupStopSequence,
        'dropStopSequence': dropStopSequence,
        'dimensionsSource': dimensionsSource,
        'cogSource': cogSource,
        'cogOffsetXMm': cogOffsetXMm,
        'cogOffsetYMm': cogOffsetYMm,
        'cogHeightMm': cogHeightMm,
        'deliveryWave': deliveryWave,
        'readyDate': readyDate,
        'travelGroup': travelGroup,
      };

  factory CargoDraft.fromDraft(Map<String, dynamic> json) => CargoDraft(
        cargoName: json['cargoName'] as String,
        quantity: json['quantity'] as String,
        weightKg: json['weightKg'] as String,
        lengthMm: json['lengthMm'] as String,
        widthMm: json['widthMm'] as String,
        heightMm: json['heightMm'] as String,
        isFragile: json['isFragile'] as bool,
        doNotStack: json['doNotStack'] as bool,
        rotationAllowed: json['rotationAllowed'] as bool,
        canLieDown: json['canLieDown'] as bool,
        supportType: json['supportType'] as String,
        saddleHeightMm: json['saddleHeightMm'] as String,
        // Nháp lưu từ bản cũ chưa có các ô này
        pickupStopSequence: json['pickupStopSequence'] as int?,
        dropStopSequence: json['dropStopSequence'] as int?,
        dimensionsSource: (json['dimensionsSource'] as String?) ?? 'Estimated',
        cogSource: (json['cogSource'] as String?) ?? 'Estimated',
        cogOffsetXMm: (json['cogOffsetXMm'] as String?) ?? '',
        cogOffsetYMm: (json['cogOffsetYMm'] as String?) ?? '',
        cogHeightMm: (json['cogHeightMm'] as String?) ?? '',
        deliveryWave: (json['deliveryWave'] as String?) ?? '1',
        readyDate: (json['readyDate'] as String?) ?? '',
        travelGroup: (json['travelGroup'] as String?) ?? '',
      );

  /// Kiện AI đọc từ tin nhắn. Ô không chắc hoặc tin không ghi thì đánh dấu để người dùng kiểm tra.
  factory CargoDraft.fromAi(Map<String, dynamic> json) {
    final Map<String, AiFlag> flags = <String, AiFlag>{};
    final Map<String, String> raws = <String, String>{};
    String read(String field) {
      final Map<String, dynamic> cell = (json[field] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final Object? value = cell['value'];
      final String? raw = cell['raw'] as String?;
      if (raw != null) raws[field] = raw;
      if ((cell['needsConfirmation'] as bool? ?? false) || value == null) {
        flags[field] = AiFlag(raw: raw, reason: (cell['reason'] as String?) ?? (value == null ? t('orderForm.aiMissing') : null));
      }
      return value == null ? '' : '$value';
    }

    final String name = (json['cargoName'] as String?) ?? '';
    if (name.isEmpty) flags['cargoName'] = AiFlag(reason: t('orderForm.aiNoName'));
    return CargoDraft(
      cargoName: name,
      quantity: read('quantity'),
      weightKg: read('weightKg'),
      lengthMm: read('lengthMm'),
      widthMm: read('widthMm'),
      heightMm: read('heightMm'),
      isFragile: (json['isFragile'] as bool?) ?? false,
      doNotStack: (json['doNotStack'] as bool?) ?? false,
      rotationAllowed: (json['rotationAllowed'] as bool?) ?? true,
      canLieDown: (json['canLieDown'] as bool?) ?? false,
      supportType: (json['supportType'] as String?) ?? 'Flat',
      aiFlags: flags,
      aiRaws: raws,
      issues: <String>[for (final dynamic issue in (json['issues'] as List<dynamic>?) ?? <dynamic>[]) issue as String],
      sourceText: json['sourceText'] as String?,
    );
  }

  /// Lỗi theo ô: tên trường → câu lỗi. Còn ô AI chưa xác nhận là lỗi, không cho lưu.
  Map<String, String> validate() {
    final Map<String, String> errors = <String, String>{};
    if (cargoName.trim().isEmpty) errors['cargoName'] = t('orderForm.errorCargoName');
    final num? quantityValue = parseNumberInput(quantity, integer: true);
    if (quantityValue == null || quantityValue.isNaN || quantityValue < 1) errors['quantity'] = t('orderForm.errorQuantity');
    final num? weight = parseNumberInput(weightKg, integer: false);
    if (weight == null || weight.isNaN || weight <= 0) errors['weightKg'] = t('orderForm.errorWeight');
    for (final MapEntry<String, String> size in <String, String>{'lengthMm': lengthMm, 'widthMm': widthMm, 'heightMm': heightMm}.entries) {
      final num? value = parseNumberInput(size.value, integer: true);
      if (value == null || value.isNaN || value <= 0) errors[size.key] = t('orderForm.errorSize');
    }
    for (final String field in aiFlags.keys) {
      errors.putIfAbsent(field, () => t('orderForm.errorAiConfirm'));
    }
    if (supportType == 'Cylinder') {
      final num? saddle = parseNumberInput(saddleHeightMm, integer: true);
      if (saddle == null || saddle.isNaN || saddle <= 0) errors['saddleHeightMm'] = t('orderForm.errorSaddle');
    }
    for (final MapEntry<String, String> offset in <String, String>{'cogOffsetXMm': cogOffsetXMm, 'cogOffsetYMm': cogOffsetYMm}.entries) {
      if (parseNumberInput(offset.value, integer: true)?.isNaN ?? false) errors[offset.key] = t('orderForm.errorCogOffset');
    }
    final num? cogHeight = parseNumberInput(cogHeightMm, integer: true);
    if (cogHeight != null && (cogHeight.isNaN || cogHeight <= 0)) errors['cogHeightMm'] = t('orderForm.errorSize');
    final num? wave = parseNumberInput(deliveryWave, integer: true);
    if (wave == null || wave.isNaN || wave < 1 || wave > 99) errors['deliveryWave'] = t('orderForm.errorWave');
    if (travelGroup.trim().length > 50) errors['travelGroup'] = t('orderForm.errorTravelGroup');
    return errors;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'cargoCode': null,
        'cargoName': cargoName.trim(),
        'category': null,
        'quantity': parseNumberInput(quantity, integer: true),
        'weightKg': parseNumberInput(weightKg, integer: false),
        'lengthMm': parseNumberInput(lengthMm, integer: true),
        'widthMm': parseNumberInput(widthMm, integer: true),
        'heightMm': parseNumberInput(heightMm, integer: true),
        'isFragile': isFragile,
        'doNotStack': doNotStack,
        'rotationAllowed': rotationAllowed,
        'supportType': supportType,
        // Chỉ đế phẳng mới được đặt nằm (backend từ chối nếu khác)
        'canLieDown': supportType == 'Flat' && canLieDown,
        'saddleHeightMm': supportType == 'Cylinder' ? parseNumberInput(saddleHeightMm, integer: true) : null,
        ..._planJson(),
      };

  Map<String, dynamic> _planJson() => <String, dynamic>{
        'pickupStopSequence': pickupStopSequence,
        'dropStopSequence': dropStopSequence,
        'cogOffsetXMm': parseNumberInput(cogOffsetXMm, integer: true),
        'cogOffsetYMm': parseNumberInput(cogOffsetYMm, integer: true),
        'cogHeightMm': parseNumberInput(cogHeightMm, integer: true),
        'dimensionsSource': dimensionsSource,
        'cogSource': cogSource,
        'deliveryWave': parseNumberInput(deliveryWave, integer: true) ?? 1,
        'readyDate': readyDate.isEmpty ? null : readyDate,
        'travelGroup': travelGroup.trim().isEmpty ? null : travelGroup.trim(),
      };

  /// Kiện nặng còn số ước lượng: bản vẽ biện pháp sẽ là bản nháp (BR-DRW-002)
  bool get drawingDraftRisk {
    final num? weight = parseNumberInput(weightKg, integer: false);
    return weight != null && !weight.isNaN && weight >= 500 && (dimensionsSource == 'Estimated' || cogSource == 'Estimated');
  }

  /// Các ô form này sửa được
  Map<String, dynamic> editableJson() => <String, dynamic>{
        'cargoName': cargoName.trim(),
        'quantity': parseNumberInput(quantity, integer: true),
        'weightKg': parseNumberInput(weightKg, integer: false),
        'lengthMm': parseNumberInput(lengthMm, integer: true),
        'widthMm': parseNumberInput(widthMm, integer: true),
        'heightMm': parseNumberInput(heightMm, integer: true),
        'isFragile': isFragile,
        'doNotStack': doNotStack,
        'rotationAllowed': rotationAllowed,
        'supportType': supportType,
        'canLieDown': supportType == 'Flat' && canLieDown,
        'saddleHeightMm': supportType == 'Cylinder' ? parseNumberInput(saddleHeightMm, integer: true) : null,
        ..._planJson(),
      };

  /// Thân lệnh sửa kiện: giữ nguyên các ô app không có, chỉ đè các ô form sửa được
  Map<String, dynamic> toUpdateJson() => <String, dynamic>{...?serverRaw, ...editableJson()};
}

class OrderFormData {
  // Khách quen: có customerId. Khách mới: isNewCustomer, backend tự lưu vào danh bạ
  bool isNewCustomer = false;
  String? customerId;
  String customerName = '';
  String customerPhone = '';
  List<StopDraft> stops = <StopDraft>[StopDraft(kind: 'Pickup'), StopDraft(kind: 'Delivery')];
  List<WorkDayDraft> workDays = <WorkDayDraft>[];
  List<CargoDraft> cargos = <CargoDraft>[];
  int? quotedAmount;
  String operatingProfile = 'Balanced';
  String notes = '';
  // Xe dùng để ước tính (nhóm phí BOT, cảnh báo quá khổ), không phải gán xe. Moóc thì chọn thêm đầu kéo
  String? estimationVehicleId;
  String? estimationVehicleLabel;
  bool estimationIsTrailer = false;
  String? estimationTractorId;
  String? estimationTractorLabel;

  OrderFormData();

  /// Đổi danh sách điểm. Kiện lưu điểm bốc, trả theo số thứ tự nên phải đánh lại số;
  /// điểm bị xóa hoặc đổi loại thì kiện về "chưa chọn"
  void changeStops(void Function() apply) {
    final List<StopDraft> before = List<StopDraft>.of(stops);
    apply();
    int? renumber(int? sequence, String kind) {
      if (sequence == null || sequence < 1 || sequence > before.length) return null;
      final String key = before[sequence - 1].key;
      final int index = stops.indexWhere((StopDraft stop) => stop.key == key);
      return index < 0 || stops[index].kind != kind ? null : index + 1;
    }

    for (final CargoDraft cargo in cargos) {
      cargo.pickupStopSequence = renumber(cargo.pickupStopSequence, 'Pickup');
      cargo.dropStopSequence = renumber(cargo.dropStopSequence, 'Delivery');
    }
  }

  /// Chỗ chèn điểm mới, như web: điểm bốc ngay sau điểm đầu, điểm đi qua trước điểm cuối, điểm trả xuống cuối
  int insertIndexFor(String kind) {
    return switch (kind) {
      'Pickup' => stops.isEmpty ? 0 : 1,
      'Via' => stops.isEmpty ? 0 : stops.length - 1,
      _ => stops.length,
    };
  }

  /// Mở đơn đã lưu để sửa. Khách không đổi được sau khi tạo (server không có lệnh đổi)
  factory OrderFormData.fromOrder(OrderDetail order) {
    return OrderFormData()
      ..customerId = order.customerId ?? ''
      ..customerName = order.customerName
      ..customerPhone = order.customerPhone
      ..stops = <StopDraft>[for (final OrderStop stop in order.stops) StopDraft.fromOrder(stop)]
      ..workDays = <WorkDayDraft>[for (final OrderWorkDay day in order.workDays) WorkDayDraft.fromOrder(day)]
      ..cargos = <CargoDraft>[for (final OrderCargo cargo in order.cargos) CargoDraft.fromOrder(cargo)]
      ..quotedAmount = order.quotedAmount?.toInt()
      ..operatingProfile = order.operatingProfile
      ..notes = order.notes ?? ''
      ..estimationVehicleId = order.estimationVehicleId
      ..estimationVehicleLabel = order.estimationVehicleLabel
      ..estimationIsTrailer = order.estimationTractorId != null
      ..estimationTractorId = order.estimationTractorId
      ..estimationTractorLabel = order.estimationTractorLabel;
  }

  Map<String, dynamic> toDraft() => <String, dynamic>{
        'isNewCustomer': isNewCustomer,
        'customerId': customerId,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'stops': <Map<String, dynamic>>[for (final StopDraft stop in stops) stop.toDraft()],
        'workDays': <Map<String, dynamic>>[for (final WorkDayDraft day in workDays) day.toDraft()],
        'cargos': <Map<String, dynamic>>[for (final CargoDraft cargo in cargos) cargo.toDraft()],
        'quotedAmount': quotedAmount,
        'operatingProfile': operatingProfile,
        'notes': notes,
        'estimationVehicleId': estimationVehicleId,
        'estimationVehicleLabel': estimationVehicleLabel,
        'estimationIsTrailer': estimationIsTrailer,
        'estimationTractorId': estimationTractorId,
        'estimationTractorLabel': estimationTractorLabel,
      };

  factory OrderFormData.fromDraft(Map<String, dynamic> json) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) read) => <T>[
          for (final dynamic row in json[key] as List<dynamic>) read(row as Map<String, dynamic>),
        ];
    return OrderFormData()
      ..isNewCustomer = json['isNewCustomer'] as bool
      ..customerId = json['customerId'] as String?
      ..customerName = json['customerName'] as String
      ..customerPhone = json['customerPhone'] as String
      ..stops = list('stops', StopDraft.fromDraft)
      ..workDays = list('workDays', WorkDayDraft.fromDraft)
      ..cargos = list('cargos', CargoDraft.fromDraft)
      ..quotedAmount = (json['quotedAmount'] as num?)?.toInt()
      ..operatingProfile = json['operatingProfile'] as String
      ..notes = json['notes'] as String
      ..estimationVehicleId = json['estimationVehicleId'] as String?
      ..estimationVehicleLabel = json['estimationVehicleLabel'] as String?
      ..estimationIsTrailer = (json['estimationIsTrailer'] as bool?) ?? false
      ..estimationTractorId = json['estimationTractorId'] as String?
      ..estimationTractorLabel = json['estimationTractorLabel'] as String?;
  }

  /// Tổng số kiện và tổng kg cho dòng tóm tắt; ô chưa nhập hay sai thì không tính
  int get totalPieces => cargos.fold(0, (int sum, CargoDraft cargo) {
        final num? quantity = parseNumberInput(cargo.quantity, integer: true);
        return sum + (quantity == null || quantity.isNaN ? 0 : quantity.toInt());
      });

  num get totalKg => cargos.fold<num>(0, (num sum, CargoDraft cargo) {
        final num? quantity = parseNumberInput(cargo.quantity, integer: true);
        final num? weight = parseNumberInput(cargo.weightKg, integer: false);
        if (quantity == null || quantity.isNaN || weight == null || weight.isNaN) return sum;
        return sum + quantity * weight;
      });

  /// Đã nhập gì chưa: chưa thì không cần giữ bản nháp
  bool get isDirty =>
      customerId != null ||
      customerName.trim().isNotEmpty ||
      customerPhone.trim().isNotEmpty ||
      stops.length != 2 ||
      stops.any((StopDraft stop) => <String>[stop.address, stop.contactName, stop.contactPhone, stop.note].any((String text) => text.trim().isNotEmpty)) ||
      workDays.isNotEmpty ||
      cargos.isNotEmpty ||
      quotedAmount != null ||
      estimationVehicleId != null ||
      notes.trim().isNotEmpty;

  /// Thứ tự điểm sai: thiếu điểm bốc hoặc trả, điểm đầu không phải điểm bốc, điểm cuối là điểm đi qua
  String? get stopOrderError {
    if (!stops.any((StopDraft stop) => stop.kind == 'Pickup') || !stops.any((StopDraft stop) => stop.kind == 'Delivery')) {
      return t('orderForm.errorNeedPickupDelivery');
    }
    if (stops.first.kind != 'Pickup') return t('orderForm.errorFirstPickup');
    if (stops.last.kind == 'Via') return t('orderForm.errorLastVia');
    return null;
  }

  /// Đủ để server nhận (khách, điểm dừng, các kiện hợp lệ); thiếu thì nháp chỉ nằm trên máy.
  /// Gửi báo giá cần thêm kiện, ngày làm, giá.
  /// Khóa: customer, stops, stop.{key}, stop.{key}.phone, days, day.{key}, cargos, cargo.{key}, quoted.
  Map<String, String> validate({required bool forQuote}) {
    final Map<String, String> errors = <String, String>{};
    if (isNewCustomer) {
      if (customerName.trim().isEmpty) {
        errors['customer'] = t('orderForm.errorCustomerName');
      } else if (!isValidCustomerPhone(customerPhone)) {
        errors['customer'] = t('orderForm.errorPhone');
      }
    } else if (customerId == null) {
      errors['customer'] = t('orderForm.errorCustomer');
    }

    if (stops.length > maxOrderStops) {
      errors['stops'] = t('orderForm.errorMaxStops', <String, Object?>{'max': maxOrderStops});
    }
    final String? orderError = stopOrderError;
    if (orderError != null) errors['stops'] = orderError;
    for (final StopDraft stop in stops) {
      if (stop.address.trim().isEmpty) errors['stop.${stop.key}'] = t('orderForm.errorAddress');
      if (stop.kind != 'Via' && stop.contactPhone.trim().isNotEmpty && !isValidCustomerPhone(stop.contactPhone)) {
        errors['stop.${stop.key}.phone'] = t('orderForm.errorPhone');
      }
    }

    final Set<String> seenDays = <String>{};
    for (final WorkDayDraft day in workDays) {
      if (day.workDate.isEmpty) {
        errors['day.${day.key}'] = t('orderForm.errorDate');
      } else if (seenDays.contains(day.workDate)) {
        errors['day.${day.key}'] = t('orderForm.errorDuplicateDate');
      } else if (day.startTime == day.endTime) {
        errors['day.${day.key}'] = t('orderForm.errorSameTime');
      }
      seenDays.add(day.workDate);
    }

    for (final CargoDraft cargo in cargos) {
      final Map<String, String> cargoErrors = cargo.validate();
      if (cargoErrors.isNotEmpty) errors['cargo.${cargo.key}'] = cargoErrors.values.first;
    }

    if (forQuote) {
      if (cargos.isEmpty) errors['cargos'] = t('orderForm.errorQuoteCargo');
      if (workDays.isEmpty) errors['days'] = t('orderForm.errorQuoteDay');
      if ((quotedAmount ?? 0) <= 0) errors['quoted'] = t('orderForm.errorQuotePrice');
    }
    return errors;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (isNewCustomer) ...<String, dynamic>{
          'quickCustomerName': customerName.trim(),
          'quickCustomerPhone': customerPhone.trim(),
        } else
          'customerPublicId': customerId,
        'stops': <Map<String, dynamic>>[for (final StopDraft stop in stops) stop.toJson()],
        'workDays': <Map<String, dynamic>>[for (final WorkDayDraft day in workDays) day.toJson()],
        'cargos': <Map<String, dynamic>>[for (final CargoDraft cargo in cargos) cargo.toJson()],
        'quotedAmount': quotedAmount,
        'estimationVehiclePublicId': estimationVehicleId,
        'estimationTractorPublicId': estimationTractorId,
        'operatingProfile': operatingProfile,
        'notes': notes.trim().isEmpty ? null : notes.trim(),
      };

  /// Yêu cầu ước tính tuyến khi mọi điểm đã có tọa độ; chưa đủ thì null (mỗi lần gọi Vietmap là một lượt tính phí)
  Map<String, dynamic>? routeRequest() {
    if (stops.length < 2 || stops.any((StopDraft stop) => !stop.hasCoordinates)) return null;
    return <String, dynamic>{
      'originLatitude': stops.first.latitude,
      'originLongitude': stops.first.longitude,
      'destinationLatitude': stops.last.latitude,
      'destinationLongitude': stops.last.longitude,
      'waypoints': <Map<String, dynamic>>[
        for (final StopDraft stop in stops.sublist(1, stops.length - 1)) <String, dynamic>{'latitude': stop.latitude, 'longitude': stop.longitude},
      ],
      'estimationVehiclePublicId': estimationVehicleId,
      'estimationTractorPublicId': estimationTractorId,
    };
  }
}
