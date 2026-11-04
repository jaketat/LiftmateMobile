// Các sheet nhập của màn tạo đơn: chọn khách, sửa điểm dừng, ngày làm, kiện.
// Sửa trên bản sao, bấm Xong mới áp vào form; chạm ngoài sheet không đóng để khỏi mất chữ đang gõ.
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:vietmap_flutter_gl/vietmap_flutter_gl.dart' show LatLng;

import '../../core/api/call.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ios.dart';
import '../../core/labels.dart';
import '../customers/customers_api.dart';
import '../fleet/fleet_api.dart';
import '../driver/trip_map.dart' show stopColor;
import 'order_actions.dart';
import 'order_form.dart';
import 'orders_api.dart';
import 'static_map.dart';
import 'stop_location_screen.dart';

/// Hàng mở bộ chọn trong sheet: nhãn bên trái, giá trị bên phải
class _PickerRow extends StatelessWidget {
  final String label;
  final String value;
  final String? error;
  final VoidCallback onTap;

  const _PickerRow({required this.label, required this.value, required this.onTap, this.error});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: AppColors.fillSoft,
            borderRadius: BorderRadius.circular(18),
            onPressed: onTap,
            child: Row(
              children: <Widget>[
                Text(label, style: TextStyle(fontSize: 16, color: AppColors.text)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    value,
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, color: IosColors.secondaryLabel),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(CupertinoIcons.chevron_up_chevron_down, size: 15, color: IosColors.tertiaryLabel),
              ],
            ),
          ),
          if (error != null) OrderSheetError(error!),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: TextStyle(fontSize: 16, color: AppColors.text))),
          CupertinoSwitch(value: value, activeTrackColor: IosColors.green, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _SheetButtons extends StatelessWidget {
  final String doneLabel;
  final VoidCallback? onDone;

  const _SheetButtons({required this.doneLabel, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 18),
        IosPillButton(label: doneLabel, onPressed: onDone),
        CupertinoButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t('common.cancel'), style: TextStyle(color: IosColors.blue)),
        ),
      ],
    );
  }
}

/// Bánh xe chọn ngày hoặc giờ kiểu iOS. Trả null khi đóng không chọn.
Future<DateTime?> pickDateTime(
  BuildContext context, {
  required CupertinoDatePickerMode mode,
  required DateTime initial,
  DateTime? minimumDate,
  DateTime? maximumDate,
}) async {
  DateTime chosen = initial;
  final bool? ok = await showCupertinoModalPopup<bool>(
    context: context,
    builder: (BuildContext context) => Container(
      height: 300,
      color: AppColors.surface,
      child: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                CupertinoButton(onPressed: () => Navigator.of(context).pop(false), child: Text(t('common.cancel'))),
                CupertinoButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(t('common.done'), style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: mode,
                use24hFormat: true,
                dateOrder: DatePickerDateOrder.dmy,
                initialDateTime: initial,
                minimumDate: minimumDate,
                maximumDate: maximumDate,
                onDateTimeChanged: (DateTime value) => chosen = value,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return ok == true ? chosen : null;
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

// ---------- Chọn khách ----------

/// Khách quen trong danh bạ, hoặc khách mới nhập nhanh tên + số điện thoại
class CustomerPick {
  final bool isNew;
  final String? id;
  final String name;
  final String phone;

  const CustomerPick({required this.isNew, this.id, required this.name, required this.phone});
}

Future<CustomerPick?> showCustomerPickerSheet(BuildContext context, {required OrderFormData form}) {
  return showOrderFormSheet<CustomerPick>(context, _CustomerSheet(form: form), dismissible: false);
}

class _CustomerSheet extends StatefulWidget {
  final OrderFormData form;

  const _CustomerSheet({required this.form});

  @override
  State<_CustomerSheet> createState() => _CustomerSheetState();
}

class _CustomerSheetState extends State<_CustomerSheet> {
  late bool isNew = widget.form.isNewCustomer;
  late final TextEditingController name = TextEditingController(text: isNew ? widget.form.customerName : '');
  late final TextEditingController phone = TextEditingController(text: isNew ? widget.form.customerPhone : '');
  String search = '';
  Timer? debounce;
  int generation = 0;
  List<Customer> results = <Customer>[];
  bool loading = true;
  String? error;
  bool triedSave = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    debounce?.cancel();
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final int current = ++generation;
    try {
      final result = await fetchCustomers(1, search);
      if (!mounted || current != generation) return;
      setState(() {
        results = result.items;
        loading = false;
        error = null;
      });
    } catch (e) {
      if (!mounted || current != generation) return;
      setState(() {
        loading = false;
        error = errorMessage(e);
      });
    }
  }

  void onSearch(String text) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 300), () {
      search = text.trim();
      setState(() => loading = true);
      load();
    });
  }

  void saveNew() {
    setState(() => triedSave = true);
    if (name.text.trim().isEmpty || !isValidCustomerPhone(phone.text)) return;
    Navigator.of(context).pop(CustomerPick(isNew: true, name: name.text.trim(), phone: phone.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return OrderFormSheet(
      title: t('orderForm.customer'),
      children: <Widget>[
        const SizedBox(height: 6),
        CupertinoSlidingSegmentedControl<bool>(
          groupValue: isNew,
          children: <bool, Widget>{
            false: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(t('orderForm.customerExisting'))),
            true: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(t('orderForm.customerNew'))),
          },
          onValueChanged: (bool? value) => setState(() => isNew = value ?? false),
        ),
        const SizedBox(height: 12),
        if (isNew) ...<Widget>[
          OrderSheetField(placeholder: t('orderForm.customerName'), controller: name, onChanged: (String _) => setState(() {})),
          if (triedSave && name.text.trim().isEmpty) OrderSheetError(t('orderForm.errorCustomerName')),
          const SizedBox(height: 10),
          OrderSheetField(
            placeholder: t('orderForm.customerPhone'),
            controller: phone,
            keyboardType: TextInputType.phone,
            onChanged: (String _) => setState(() {}),
          ),
          if (triedSave && !isValidCustomerPhone(phone.text))
            OrderSheetError(t('orderForm.errorPhone'))
          else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(t('orderForm.customerNewNote'), style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel)),
            ),
          _SheetButtons(doneLabel: t('common.done'), onDone: saveNew),
        ] else ...<Widget>[
          CupertinoSearchTextField(placeholder: t('orderForm.customerSearch'), style: TextStyle(color: AppColors.text), onChanged: onSearch),
          const SizedBox(height: 8),
          if (loading) const Padding(padding: EdgeInsets.all(24), child: CupertinoActivityIndicator()),
          if (error != null) OrderSheetError(error!),
          if (!loading && error == null && results.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(t('orderForm.customerNotFound'), textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: IosColors.secondaryLabel)),
            ),
          for (final Customer customer in results)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.centerLeft,
              onPressed: () => Navigator.of(context).pop(
                CustomerPick(isNew: false, id: customer.publicId, name: customer.customerName, phone: customer.phone),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(customer.customerName, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
                  Text('${customer.customerCode} · ${customer.phone}', style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel)),
                ],
              ),
            ),
          CupertinoButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t('common.cancel'), style: TextStyle(color: IosColors.blue)),
          ),
        ],
      ],
    );
  }
}

// ---------- Xe dự kiến ----------

/// Chọn xe để ước tính. [vehicle] null là bỏ chọn
class EstimationVehiclePick {
  final Vehicle? vehicle;

  const EstimationVehiclePick(this.vehicle);
}

Future<EstimationVehiclePick?> showEstimationVehicleSheet(BuildContext context, {required bool tractors, required String noneLabel}) {
  return showOrderFormSheet<EstimationVehiclePick>(context, _EstimationVehicleSheet(tractors: tractors, noneLabel: noneLabel));
}

class _EstimationVehicleSheet extends StatefulWidget {
  final bool tractors;
  final String noneLabel;

  const _EstimationVehicleSheet({required this.tractors, required this.noneLabel});

  @override
  State<_EstimationVehicleSheet> createState() => _EstimationVehicleSheetState();
}

class _EstimationVehicleSheetState extends State<_EstimationVehicleSheet> {
  // Như web: mọi xe của công ty, không lọc trạng thái. Xe này chỉ để ước tính, gán xe thật ở bước điều phối
  late final Future<List<Vehicle>> vehicles = fetchVehicles(1, '', widget.tractors ? 'TractorHead' : null, null, pageSize: 100).then((result) => result.items);

  Widget row(String title, String? subtitle, EstimationVehiclePick pick) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: 10),
      alignment: Alignment.centerLeft,
      onPressed: () => Navigator.of(context).pop(pick),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
          if (subtitle != null) Text(subtitle, style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OrderFormSheet(
      title: widget.tractors ? t('orderForm.estimationTractor') : t('orderForm.estimationVehicle'),
      children: <Widget>[
        row(widget.noneLabel, null, const EstimationVehiclePick(null)),
        FutureBuilder<List<Vehicle>>(
          future: vehicles,
          builder: (BuildContext context, AsyncSnapshot<List<Vehicle>> snapshot) {
            if (snapshot.hasError) return OrderSheetError(errorMessage(snapshot.error!));
            if (!snapshot.hasData) return const Padding(padding: EdgeInsets.all(24), child: CupertinoActivityIndicator());
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final Vehicle vehicle in snapshot.data!) row(vehicle.title, label(vehicleBaseTypeLabels, vehicle.baseType), EstimationVehiclePick(vehicle)),
              ],
            );
          },
        ),
        CupertinoButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t('common.cancel'), style: TextStyle(color: IosColors.blue)),
        ),
      ],
    );
  }
}

// ---------- Điểm dừng ----------

/// Kết quả sửa điểm: bản đã sửa, hoặc lệnh xóa. Đổi thứ tự thì kéo ngay trên danh sách điểm
class StopSheetResult {
  final StopDraft? stop;
  final bool delete;

  const StopSheetResult({this.stop, this.delete = false});
}

Future<StopSheetResult?> showStopSheet(BuildContext context, {required StopDraft stop, required int index, required int total, LatLng? near}) {
  return showOrderFormSheet<StopSheetResult>(context, _StopSheet(stop: stop, index: index, total: total, near: near), dismissible: false);
}

class _StopSheet extends StatefulWidget {
  final StopDraft stop;
  final int index;
  final int total;
  // Điểm gần đó (điểm trước của đơn): mở bản đồ ở đây khi điểm này chưa có vị trí
  final LatLng? near;

  const _StopSheet({required this.stop, required this.index, required this.total, this.near});

  @override
  State<_StopSheet> createState() => _StopSheetState();
}

class _StopSheetState extends State<_StopSheet> {
  late final StopDraft draft = widget.stop.copy();
  late final TextEditingController address = TextEditingController(text: draft.address);
  late final TextEditingController contactName = TextEditingController(text: draft.contactName);
  late final TextEditingController contactPhone = TextEditingController(text: draft.contactPhone);
  late final TextEditingController note = TextEditingController(text: draft.note);
  Timer? debounce;
  int generation = 0;
  List<AddressSuggestion> suggestions = <AddressSuggestion>[];
  bool resolving = false;
  String? searchNote;
  bool triedSave = false;

  @override
  void dispose() {
    debounce?.cancel();
    address.dispose();
    contactName.dispose();
    contactPhone.dispose();
    note.dispose();
    super.dispose();
  }

  String vietmapError(ApiException error) {
    return switch (error.code) {
      'EXTERNAL_API_QUOTA_EXCEEDED' => t('orderForm.addressQuota'),
      'EXTERNAL_API_RATE_LIMITED' => t('orderForm.addressRateLimited'),
      _ => t('orderForm.addressNoResult'),
    };
  }

  // Mỗi lần gọi là một lượt tính tiền: chỉ gọi khi ngừng gõ 400 ms và đủ 3 ký tự, kết quả cũ về sau thì bỏ
  void onAddressChanged(String text) {
    debounce?.cancel();
    // Gõ lại là bỏ tọa độ cũ: tránh địa chỉ một nơi mà tọa độ nơi khác
    setState(() {
      draft.address = text;
      draft.latitude = null;
      draft.longitude = null;
      searchNote = null;
      if (text.trim().length < 3) suggestions = <AddressSuggestion>[];
    });
    final int current = ++generation;
    if (text.trim().length < 3) return;
    debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final List<AddressSuggestion> found = await searchAddresses(text.trim());
        if (!mounted || current != generation) return;
        setState(() {
          suggestions = found;
          searchNote = found.isEmpty ? t('orderForm.addressNoResult') : null;
        });
      } on ApiException catch (e) {
        if (!mounted || current != generation) return;
        setState(() => searchNote = vietmapError(e));
      }
    });
  }

  Future<void> choose(AddressSuggestion item) async {
    debounce?.cancel();
    final int current = ++generation;
    FocusScope.of(context).unfocus();
    setState(() {
      suggestions = <AddressSuggestion>[];
      resolving = true;
      draft.address = item.display;
      address.text = item.display;
    });
    try {
      final PlaceDetail place = await fetchPlace(item.refId);
      if (!mounted || current != generation) return;
      setState(() {
        draft.address = place.display.isEmpty ? item.display : place.display;
        address.text = draft.address;
        draft.latitude = place.latitude;
        draft.longitude = place.longitude;
        resolving = false;
      });
    } on ApiException catch (e) {
      if (!mounted || current != generation) return;
      setState(() {
        resolving = false;
        searchNote = e.code == 'PLACE_UNAVAILABLE' ? t('orderForm.addressNoCoordinates') : vietmapError(e);
      });
    }
  }

  Future<void> pickOnMap() async {
    FocusScope.of(context).unfocus();
    final PickedLocation? picked = await pickStopLocation(
      context,
      kind: draft.kind,
      number: widget.index + 1,
      initial: draft.hasCoordinates ? PickedLocation(address: draft.address, latitude: draft.latitude!, longitude: draft.longitude!) : null,
      near: widget.near,
    );
    if (picked == null || picked.isManual || !mounted) return;
    debounce?.cancel();
    generation++;
    setState(() {
      suggestions = <AddressSuggestion>[];
      searchNote = null;
      resolving = false;
      draft.address = picked.address;
      address.text = picked.address;
      draft.latitude = picked.latitude;
      draft.longitude = picked.longitude;
    });
  }

  Future<void> pickKind() async {
    final String? kind = await showIosActionSheet<String>(
      context,
      options: <IosSheetOption<String>>[
        for (final String value in const <String>['Pickup', 'Delivery', 'Via']) IosSheetOption<String>(value, label(stopKindLabels, value)),
      ],
    );
    if (kind != null && mounted) setState(() => draft.kind = kind);
  }

  bool get phoneInvalid => draft.kind != 'Via' && contactPhone.text.trim().isNotEmpty && !isValidCustomerPhone(contactPhone.text);

  void save() {
    setState(() => triedSave = true);
    if (draft.address.trim().isEmpty || phoneInvalid) return;
    draft.contactName = contactName.text;
    draft.contactPhone = contactPhone.text;
    draft.note = note.text;
    Navigator.of(context).pop(StopSheetResult(stop: draft));
  }

  @override
  Widget build(BuildContext context) {
    return OrderFormSheet(
      title: t('orderForm.stopTitle', <String, Object?>{'number': widget.index + 1}),
      children: <Widget>[
        _PickerRow(label: t('orderForm.stopKind'), value: label(stopKindLabels, draft.kind), onTap: pickKind),
        const SizedBox(height: 10),
        OrderSheetField(placeholder: t('orderForm.addressHint'), controller: address, maxLines: 2, autocorrect: false, onChanged: onAddressChanged),
        if (triedSave && draft.address.trim().isEmpty) OrderSheetError(t('orderForm.errorAddress')),
        for (final AddressSuggestion item in suggestions)
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            alignment: Alignment.centerLeft,
            onPressed: () => choose(item),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(item.name ?? item.display, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text)),
                if (item.name != null) Text(item.display, style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel)),
                if (item.displayOld != null)
                  Text(t('orderForm.addressOld', <String, Object?>{'name': item.displayOld}), style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel)),
              ],
            ),
          ),
        if (resolving)
          const Padding(padding: EdgeInsets.only(top: 6), child: Align(alignment: Alignment.centerLeft, child: CupertinoActivityIndicator()))
        else if (searchNote != null || draft.address.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              searchNote ?? (draft.hasCoordinates ? t('orderForm.addressHasCoordinates') : t('orderForm.addressPickSuggestion')),
              style: TextStyle(
                fontSize: 13,
                color: searchNote != null ? AppColors.warnText : (draft.hasCoordinates ? AppColors.okText : IosColors.secondaryLabel),
              ),
            ),
          ),
        if (stopMapAvailable) ...<Widget>[
          if (draft.hasCoordinates)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: StaticRouteMap(
                  height: 130,
                  semanticLabel: t('orderForm.adjustOnMap'),
                  stops: <StaticMapStop>[
                    StaticMapStop(point: LatLng(draft.latitude!, draft.longitude!), color: stopColor(draft.kind), label: '${widget.index + 1}'),
                  ],
                  onTap: pickOnMap,
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 8),
              minimumSize: const Size(44, 40),
              onPressed: pickOnMap,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(CupertinoIcons.map_pin_ellipse, size: 20, color: IosColors.blue),
                  const SizedBox(width: 6),
                  Text(draft.hasCoordinates ? t('orderForm.adjustOnMap') : t('orderForm.pickOnMap'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: IosColors.blue)),
                ],
              ),
            ),
          ),
        ],
        if (draft.kind == 'Via')
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(t('orderForm.viaNote'), style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel)),
          )
        else ...<Widget>[
          const SizedBox(height: 10),
          OrderSheetField(placeholder: t('orderForm.contactName'), controller: contactName, onChanged: (String _) {}),
          const SizedBox(height: 10),
          OrderSheetField(
            placeholder: t('orderForm.contactPhone'),
            controller: contactPhone,
            keyboardType: TextInputType.phone,
            onChanged: (String _) => setState(() {}),
          ),
          if (triedSave && phoneInvalid) OrderSheetError(t('orderForm.errorPhone')),
        ],
        if (draft.kind == 'Delivery') ...<Widget>[
          const SizedBox(height: 12),
          Text(t('orderForm.unloadMethod'), style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel)),
          const SizedBox(height: 6),
          CupertinoSlidingSegmentedControl<String>(
            groupValue: draft.unloadMethod,
            children: <String, Widget>{
              'Crane': Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(t('orderForm.unloadCrane'))),
              'ForkliftFromRear': Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(t('orderForm.unloadForklift'))),
            },
            onValueChanged: (String? value) => setState(() => draft.unloadMethod = value ?? 'Crane'),
          ),
        ],
        const SizedBox(height: 10),
        OrderSheetField(placeholder: t('orderForm.stopNote'), controller: note, maxLines: 2, onChanged: (String _) {}),
        const SizedBox(height: 6),
        if (widget.total > 2)
          Align(
            alignment: Alignment.centerRight,
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: () => Navigator.of(context).pop(const StopSheetResult(delete: true)),
              child: Text(t('orderForm.delete'), style: TextStyle(fontSize: 15, color: IosColors.red)),
            ),
          ),
        _SheetButtons(doneLabel: t('orderForm.saveStop'), onDone: save),
      ],
    );
  }
}

// ---------- Ngày làm ----------

/// Trả ngày đã sửa; [deleted] bật khi người dùng xóa ngày này
class WorkDaySheetResult {
  final WorkDayDraft? day;
  final bool deleted;

  const WorkDaySheetResult({this.day, this.deleted = false});
}

Future<WorkDaySheetResult?> showWorkDaySheet(BuildContext context, {required WorkDayDraft day, required bool isNew}) {
  return showOrderFormSheet<WorkDaySheetResult>(context, _WorkDaySheet(day: day, isNew: isNew), dismissible: false);
}

class _WorkDaySheet extends StatefulWidget {
  final WorkDayDraft day;
  final bool isNew;

  const _WorkDaySheet({required this.day, required this.isNew});

  @override
  State<_WorkDaySheet> createState() => _WorkDaySheetState();
}

class _WorkDaySheetState extends State<_WorkDaySheet> {
  late final WorkDayDraft draft = widget.day.copy();
  late final TextEditingController note = TextEditingController(text: draft.note);
  bool triedSave = false;

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await pickDateTime(
      context,
      mode: CupertinoDatePickerMode.date,
      initial: DateTime.tryParse(draft.workDate) ?? DateTime(now.year, now.month, now.day),
    );
    if (picked != null && mounted) {
      setState(() => draft.workDate = '${picked.year}-${_twoDigits(picked.month)}-${_twoDigits(picked.day)}');
    }
  }

  Future<void> pickTime({required bool start}) async {
    final List<String> parts = (start ? draft.startTime : draft.endTime).split(':');
    final DateTime? picked = await pickDateTime(
      context,
      mode: CupertinoDatePickerMode.time,
      initial: DateTime(2000, 1, 1, int.parse(parts[0]), int.parse(parts[1])),
    );
    if (picked == null || !mounted) return;
    final String text = '${_twoDigits(picked.hour)}:${_twoDigits(picked.minute)}';
    setState(() {
      if (start) {
        draft.startTime = text;
      } else {
        draft.endTime = text;
      }
    });
  }

  void save() {
    setState(() => triedSave = true);
    if (draft.workDate.isEmpty || draft.startTime == draft.endTime) return;
    draft.note = note.text;
    Navigator.of(context).pop(WorkDaySheetResult(day: draft));
  }

  @override
  Widget build(BuildContext context) {
    // Giờ kết thúc nhỏ hơn giờ bắt đầu là ca qua đêm
    final bool overnight = draft.endTime.compareTo(draft.startTime) < 0;
    return OrderFormSheet(
      title: t('orderForm.workDay'),
      children: <Widget>[
        _PickerRow(
          label: t('orderForm.date'),
          value: draft.workDate.isEmpty ? t('common.choose') : formatDate(draft.workDate),
          error: triedSave && draft.workDate.isEmpty ? t('orderForm.errorDate') : null,
          onTap: pickDate,
        ),
        _PickerRow(label: t('orderForm.startTime'), value: draft.startTime, onTap: () => pickTime(start: true)),
        _PickerRow(
          label: t('orderForm.endTime'),
          value: overnight ? '${draft.endTime} ${t('orderDetail.overnight')}' : draft.endTime,
          error: triedSave && draft.startTime == draft.endTime ? t('orderForm.errorSameTime') : null,
          onTap: () => pickTime(start: false),
        ),
        const SizedBox(height: 10),
        OrderSheetField(placeholder: t('orderForm.dayNote'), controller: note, onChanged: (String _) {}),
        if (!widget.isNew)
          Align(
            alignment: Alignment.centerRight,
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: () => Navigator.of(context).pop(const WorkDaySheetResult(deleted: true)),
              child: Text(t('orderForm.delete'), style: TextStyle(fontSize: 15, color: IosColors.red)),
            ),
          ),
        _SheetButtons(doneLabel: t('common.done'), onDone: save),
      ],
    );
  }
}

// ---------- Kiện hàng ----------

class CargoSheetResult {
  final CargoDraft? cargo;
  final bool deleted;

  const CargoSheetResult({this.cargo, this.deleted = false});
}

Future<CargoSheetResult?> showCargoSheet(BuildContext context, {required CargoDraft cargo, required bool isNew, required List<StopDraft> stops}) {
  return showOrderFormSheet<CargoSheetResult>(context, _CargoSheet(cargo: cargo, isNew: isNew, stops: stops), dismissible: false);
}

class _CargoSheet extends StatefulWidget {
  final CargoDraft cargo;
  final bool isNew;
  final List<StopDraft> stops;

  const _CargoSheet({required this.cargo, required this.isNew, required this.stops});

  @override
  State<_CargoSheet> createState() => _CargoSheetState();
}

class _CargoSheetState extends State<_CargoSheet> {
  late final CargoDraft draft = widget.cargo.copy();
  late final TextEditingController name = TextEditingController(text: draft.cargoName);
  late final TextEditingController quantity = TextEditingController(text: draft.quantity);
  late final TextEditingController weight = TextEditingController(text: draft.weightKg);
  late final TextEditingController length = TextEditingController(text: draft.lengthMm);
  late final TextEditingController width = TextEditingController(text: draft.widthMm);
  late final TextEditingController height = TextEditingController(text: draft.heightMm);
  late final TextEditingController saddle = TextEditingController(text: draft.saddleHeightMm);
  late final TextEditingController cogX = TextEditingController(text: draft.cogOffsetXMm);
  late final TextEditingController cogY = TextEditingController(text: draft.cogOffsetYMm);
  late final TextEditingController cogHeight = TextEditingController(text: draft.cogHeightMm);
  late final TextEditingController wave = TextEditingController(text: draft.deliveryWave);
  late final TextEditingController group = TextEditingController(text: draft.travelGroup);
  // Mở sẵn khi kiện đã có thông tin khác mặc định, như web
  late bool heavyOpen = draft.supportType != 'Flat' ||
      draft.cogOffsetXMm.isNotEmpty ||
      draft.cogOffsetYMm.isNotEmpty ||
      draft.cogHeightMm.isNotEmpty ||
      draft.dimensionsSource != 'Estimated' ||
      draft.cogSource != 'Estimated' ||
      draft.deliveryWave != '1' ||
      draft.readyDate.isNotEmpty ||
      draft.travelGroup.isNotEmpty;
  bool triedSave = false;

  @override
  void dispose() {
    name.dispose();
    quantity.dispose();
    weight.dispose();
    length.dispose();
    width.dispose();
    height.dispose();
    saddle.dispose();
    cogX.dispose();
    cogY.dispose();
    cogHeight.dispose();
    wave.dispose();
    group.dispose();
    super.dispose();
  }

  void changed(void Function() apply) => setState(apply);

  static const List<String> supportTypes = <String>['Flat', 'WheelsOrTracks', 'Cylinder'];
  static const List<String> dataSources = <String>['Estimated', 'Measured', 'Manufacturer'];

  String supportLabel(String value) => switch (value) {
        'WheelsOrTracks' => t('orderForm.supportWheels'),
        'Cylinder' => t('orderForm.supportCylinder'),
        _ => t('orderForm.supportFlat'),
      };

  String sourceLabel(String value) => switch (value) {
        'Measured' => t('orderForm.sourceMeasured'),
        'Manufacturer' => t('orderForm.sourceManufacturer'),
        _ => t('orderForm.sourceEstimated'),
      };

  Future<String?> pickOption(String title, List<String> values, String Function(String) labelOf) {
    return showIosActionSheet<String>(
      context,
      title: title,
      options: <IosSheetOption<String>>[for (final String value in values) IosSheetOption<String>(value, labelOf(value))],
    );
  }

  String stopLabel(int sequence) {
    final StopDraft stop = widget.stops[sequence - 1];
    return t('orderForm.stopOption', <String, Object?>{
      'number': sequence,
      'address': stop.address.trim().isEmpty ? t('orderForm.stopOptionEmpty') : stop.address.trim(),
    });
  }

  // Đơn có nhiều điểm bốc hoặc trả thì kiện phải chọn điểm; một bốc một trả thì khỏi chọn
  Widget? stopPicker(String title, String kind, int? value, void Function(int?) apply) {
    final List<int> sequences = <int>[
      for (int index = 0; index < widget.stops.length; index++)
        if (widget.stops[index].kind == kind) index + 1,
    ];
    if (sequences.length < 2) return null;
    return _PickerRow(
      label: title,
      value: value == null || value > widget.stops.length ? t('orderForm.stopUnset') : stopLabel(value),
      onTap: () async {
        final String? picked = await pickOption(title, <String>['0', for (final int sequence in sequences) '$sequence'], (String option) {
          return option == '0' ? t('orderForm.stopUnset') : stopLabel(int.parse(option));
        });
        if (picked != null && mounted) setState(() => apply(picked == '0' ? null : int.parse(picked)));
      },
    );
  }

  Future<void> pickReadyDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await pickDateTime(context, mode: CupertinoDatePickerMode.date, initial: DateTime.tryParse(draft.readyDate) ?? DateTime(now.year, now.month, now.day));
    if (picked != null && mounted) {
      setState(() => draft.readyDate = '${picked.year}-${_twoDigits(picked.month)}-${_twoDigits(picked.day)}');
    }
  }

  void save() {
    setState(() {
      triedSave = true;
      // Lỗi nằm trong thẻ hàng nặng thì mở ra cho thấy
      final Map<String, String> errors = draft.validate();
      if (<String>['saddleHeightMm', 'cogOffsetXMm', 'cogOffsetYMm', 'cogHeightMm', 'deliveryWave', 'travelGroup'].any(errors.containsKey)) heavyOpen = true;
    });
    if (draft.validate().isNotEmpty) return;
    Navigator.of(context).pop(CargoSheetResult(cargo: draft));
  }

  Widget numberField(String field, String placeholder, TextEditingController controller, void Function(String) apply, {bool decimal = false, bool signed = false}) {
    final String? error = triedSave ? draft.validate()[field] : null;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Đã có số thì chữ gợi ý biến mất, phải có nhãn mới biết ô gì
          if (controller.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text(placeholder, style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel)),
            ),
          OrderSheetField(
            placeholder: placeholder,
            controller: controller,
            keyboardType: signed
                ? const TextInputType.numberWithOptions(signed: true)
                : (decimal ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.number),
            onChanged: (String value) => changed(() => apply(value)),
          ),
          if (error != null) OrderSheetError(error),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OrderFormSheet(
      title: t('orderForm.cargo'),
      children: <Widget>[
        const SizedBox(height: 6),
        OrderSheetField(
          placeholder: t('orderForm.cargoName'),
          controller: name,
          onChanged: (String value) => changed(() => draft.cargoName = value),
        ),
        if (triedSave && draft.validate()['cargoName'] != null) OrderSheetError(draft.validate()['cargoName']!),
        numberField('quantity', t('orderForm.quantity'), quantity, (String v) => draft.quantity = v),
        numberField('weightKg', t('orderForm.weight'), weight, (String v) => draft.weightKg = v, decimal: true),
        numberField('lengthMm', t('orderForm.length'), length, (String v) => draft.lengthMm = v),
        numberField('widthMm', t('orderForm.width'), width, (String v) => draft.widthMm = v),
        numberField('heightMm', t('orderForm.height'), height, (String v) => draft.heightMm = v),
        const SizedBox(height: 6),
        _SwitchRow(label: t('orderDetail.fragile'), value: draft.isFragile, onChanged: (bool v) => setState(() => draft.isFragile = v)),
        _SwitchRow(label: t('orderDetail.doNotStack'), value: draft.doNotStack, onChanged: (bool v) => setState(() => draft.doNotStack = v)),
        _SwitchRow(label: t('orderForm.rotationAllowed'), value: draft.rotationAllowed, onChanged: (bool v) => setState(() => draft.rotationAllowed = v)),
        // Chỉ đế phẳng mới được đặt nằm
        if (draft.supportType == 'Flat') _SwitchRow(label: t('orderForm.canLieDown'), value: draft.canLieDown, onChanged: (bool v) => setState(() => draft.canLieDown = v)),
        ?stopPicker(t('orderForm.pickupAt'), 'Pickup', draft.pickupStopSequence, (int? v) => draft.pickupStopSequence = v),
        ?stopPicker(t('orderForm.dropAt'), 'Delivery', draft.dropStopSequence, (int? v) => draft.dropStopSequence = v),
        CupertinoButton(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.centerLeft,
          onPressed: () => setState(() => heavyOpen = !heavyOpen),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(t('orderForm.heavyTag'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
                    if (draft.drawingDraftRisk) Text(t('orderForm.heavyRisk'), style: TextStyle(fontSize: 13, height: 1.35, color: AppColors.warnText)),
                  ],
                ),
              ),
              Icon(heavyOpen ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down, size: 18, color: IosColors.tertiaryLabel),
            ],
          ),
        ),
        if (heavyOpen) ...<Widget>[
          _PickerRow(
            label: t('orderForm.supportType'),
            value: supportLabel(draft.supportType),
            onTap: () async {
              final String? picked = await pickOption(t('orderForm.supportType'), supportTypes, supportLabel);
              if (picked == null || !mounted) return;
              setState(() {
                draft.supportType = picked;
                if (picked != 'Flat') draft.canLieDown = false;
              });
            },
          ),
          if (draft.supportType == 'Cylinder') numberField('saddleHeightMm', t('orderForm.saddleHeight'), saddle, (String v) => draft.saddleHeightMm = v),
          _PickerRow(
            label: t('orderForm.dimensionsSource'),
            value: sourceLabel(draft.dimensionsSource),
            onTap: () async {
              final String? picked = await pickOption(t('orderForm.dimensionsSource'), dataSources, sourceLabel);
              if (picked != null && mounted) setState(() => draft.dimensionsSource = picked);
            },
          ),
          _PickerRow(
            label: t('orderForm.cogSource'),
            value: sourceLabel(draft.cogSource),
            onTap: () async {
              final String? picked = await pickOption(t('orderForm.cogSource'), dataSources, sourceLabel);
              if (picked != null && mounted) setState(() => draft.cogSource = picked);
            },
          ),
          numberField('cogOffsetXMm', t('orderForm.cogOffsetX'), cogX, (String v) => draft.cogOffsetXMm = v, signed: true),
          numberField('cogOffsetYMm', t('orderForm.cogOffsetY'), cogY, (String v) => draft.cogOffsetYMm = v, signed: true),
          numberField('cogHeightMm', t('orderForm.cogHeight'), cogHeight, (String v) => draft.cogHeightMm = v),
          numberField('deliveryWave', t('orderForm.deliveryWave'), wave, (String v) => draft.deliveryWave = v),
          const SizedBox(height: 10),
          _PickerRow(
            label: t('orderForm.readyDate'),
            value: draft.readyDate.isEmpty ? t('orderForm.readyNow') : formatDate(draft.readyDate),
            onTap: pickReadyDate,
          ),
          if (draft.readyDate.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(44, 32),
                onPressed: () => setState(() => draft.readyDate = ''),
                child: Text(t('orderForm.readyNow'), style: TextStyle(fontSize: 14, color: IosColors.blue)),
              ),
            ),
          const SizedBox(height: 10),
          OrderSheetField(placeholder: t('orderForm.travelGroup'), controller: group, maxLength: 50, onChanged: (String v) => changed(() => draft.travelGroup = v)),
          if (triedSave && draft.validate()['travelGroup'] != null) OrderSheetError(draft.validate()['travelGroup']!),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(t('orderForm.heavyNote'), style: TextStyle(fontSize: 13, height: 1.35, color: IosColors.secondaryLabel)),
          ),
        ],
        if (!widget.isNew)
          Align(
            alignment: Alignment.centerRight,
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: () => Navigator.of(context).pop(const CargoSheetResult(deleted: true)),
              child: Text(t('orderForm.delete'), style: TextStyle(fontSize: 15, color: IosColors.red)),
            ),
          ),
        _SheetButtons(doneLabel: t('common.done'), onDone: save),
      ],
    );
  }
}
