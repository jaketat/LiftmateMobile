// Chọn điểm dừng trên bản đồ, kiểu Grab: kéo bản đồ, ghim đứng giữa màn; hoặc gõ tìm rồi bản đồ bay tới đó.
// Đọc địa chỉ từ toạ độ bằng dịch vụ của hệ điều hành (miễn phí): backend chưa có lệnh này, khóa Vietmap trong app chỉ vẽ được bản đồ.
// Tên phường xã có thể theo địa giới cũ nên ô địa chỉ luôn sửa được trước khi chọn.
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:vietmap_flutter_gl/vietmap_flutter_gl.dart';

import '../../core/api/call.dart';
import '../../core/env.dart';
import '../../core/i18n.dart';
import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../core/widgets/ios.dart';
import '../../core/widgets/page_transition.dart';
import '../driver/trip_map.dart' show defaultMapCenter, mapStyleUrl, stopColor;
import 'orders_api.dart';

class PickedLocation {
  final String address;
  final double latitude;
  final double longitude;

  // Người dùng chọn gõ tay địa chỉ: chưa có toạ độ, tuyến chưa tính (như web)
  final bool isManual;

  const PickedLocation({required this.address, required this.latitude, required this.longitude}) : isManual = false;

  const PickedLocation.manual()
      : address = '',
        latitude = 0,
        longitude = 0,
        isManual = true;
}

/// Có khóa bản đồ thì mới có màn này; không có thì chỉ nhập chữ như trước
bool get stopMapAvailable => Env.vietmapKey.isNotEmpty;

Future<PickedLocation?> pickStopLocation(BuildContext context, {required String kind, required int number, PickedLocation? initial, LatLng? near}) {
  return Navigator.of(context, rootNavigator: true).push<PickedLocation>(
    MaterialPageRoute<PickedLocation>(builder: (BuildContext context) => StopLocationScreen(kind: kind, number: number, initial: initial, near: near)),
  );
}

/// Ghép địa chỉ từ kết quả của hệ điều hành: bỏ ô trống và ô trùng (tên điểm hay trùng tên đường)
String formatPlacemark(List<String?> parts) {
  final List<String> result = <String>[];
  for (final String? part in parts) {
    final String text = (part ?? '').trim();
    if (text.isEmpty || result.any((String seen) => seen.toLowerCase().contains(text.toLowerCase()))) continue;
    result.add(text);
  }
  return result.join(', ');
}

class StopLocationScreen extends StatefulWidget {
  final String kind;
  final int number;
  final PickedLocation? initial;
  final LatLng? near;

  const StopLocationScreen({super.key, required this.kind, required this.number, this.initial, this.near});

  @override
  State<StopLocationScreen> createState() => _StopLocationScreenState();
}

class _StopLocationScreenState extends State<StopLocationScreen> {
  static final geo.Geocoding geocoder = geo.Geocoding(locale: const Locale('vi', 'VN'));

  VietmapController? map;
  late LatLng center = widget.initial == null ? (widget.near ?? defaultMapCenter) : LatLng(widget.initial!.latitude, widget.initial!.longitude);
  late final TextEditingController address = TextEditingController(text: widget.initial?.address ?? '');
  final TextEditingController search = TextEditingController();
  final FocusNode searchFocus = FocusNode();
  bool moving = false;
  bool resolving = false;
  bool addressFailed = false;
  // Địa chỉ đã có (mở lại điểm cũ, vừa chọn gợi ý): bản đồ dừng lại thì không đọc đè lên
  late bool keepAddress = widget.initial != null;
  int reverseGeneration = 0;
  Timer? searchDebounce;
  int searchGeneration = 0;
  List<AddressSuggestion> suggestions = <AddressSuggestion>[];
  String? searchNote;

  @override
  void initState() {
    super.initState();
    if (widget.initial == null && widget.near == null) moveToLastKnown();
  }

  @override
  void dispose() {
    searchDebounce?.cancel();
    address.dispose();
    search.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  // Chỉ dùng khi đã có quyền sẵn: chưa bấm gì thì không bật hộp xin quyền
  Future<void> moveToLastKnown() async {
    try {
      final LocationPermission permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) return;
      final Position? position = await Geolocator.getLastKnownPosition();
      if (position != null && mounted) fly(LatLng(position.latitude, position.longitude));
    } catch (error) {
      debugPrint('Không lấy được vị trí gần nhất: $error');
    }
  }

  Future<void> goToMe() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (!await Geolocator.isLocationServiceEnabled() || permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) showIosToast(context, t('orderForm.mapLocationDenied'), isError: true);
        return;
      }
      final Position position = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)));
      keepAddress = false;
      if (mounted) fly(LatLng(position.latitude, position.longitude));
    } catch (error) {
      debugPrint('Không lấy được vị trí: $error');
      if (mounted) showIosToast(context, t('orderForm.mapLocationDenied'), isError: true);
    }
  }

  void fly(LatLng point) {
    center = point;
    map?.animateCamera(CameraUpdate.newLatLngZoom(point, 16), duration: const Duration(milliseconds: 500));
  }

  void onCameraMove(CameraPosition position) {
    if (!moving && mounted) setState(() => moving = true);
  }

  void onCameraIdle() {
    final LatLng? target = map?.cameraPosition?.target;
    if (target == null || !mounted) return;
    setState(() {
      moving = false;
      center = target;
    });
    if (keepAddress) {
      keepAddress = false;
      return;
    }
    readAddress(target);
  }

  Future<void> readAddress(LatLng point) async {
    final int current = ++reverseGeneration;
    setState(() {
      resolving = true;
      addressFailed = false;
    });
    String text = '';
    try {
      final List<geo.Placemark> found = await geocoder.placemarkFromCoordinates(point.latitude, point.longitude);
      if (found.isNotEmpty) {
        final geo.Placemark place = found.first;
        text = formatPlacemark(<String?>[place.name, place.street, place.subLocality, place.locality, place.subAdministrativeArea, place.administrativeArea]);
      }
    } catch (error) {
      debugPrint('Không đọc được địa chỉ từ toạ độ: $error');
    }
    if (!mounted || current != reverseGeneration) return;
    setState(() {
      resolving = false;
      address.text = text;
      addressFailed = text.isEmpty;
    });
  }

  // Mỗi lần gọi là một lượt tính tiền: chỉ gọi khi ngừng gõ 400 ms và đủ 3 ký tự
  void onSearchChanged(String text) {
    searchDebounce?.cancel();
    final int current = ++searchGeneration;
    if (text.trim().length < 3) {
      setState(() {
        suggestions = <AddressSuggestion>[];
        searchNote = null;
      });
      return;
    }
    searchDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final List<AddressSuggestion> found = await searchAddresses(text.trim());
        if (!mounted || current != searchGeneration) return;
        setState(() {
          suggestions = found;
          searchNote = found.isEmpty ? t('orderForm.addressNoResult') : null;
        });
      } on ApiException catch (e) {
        if (mounted && current == searchGeneration) setState(() => searchNote = e.message);
      }
    });
  }

  Future<void> choose(AddressSuggestion item) async {
    searchDebounce?.cancel();
    final int current = ++searchGeneration;
    FocusScope.of(context).unfocus();
    setState(() {
      suggestions = <AddressSuggestion>[];
      searchNote = null;
      resolving = true;
      addressFailed = false;
      address.text = item.display;
      search.text = item.name ?? item.display;
    });
    reverseGeneration++;
    try {
      final PlaceDetail place = await fetchPlace(item.refId);
      if (!mounted || current != searchGeneration) return;
      setState(() {
        resolving = false;
        address.text = place.display.isEmpty ? item.display : place.display;
      });
      keepAddress = true;
      fly(LatLng(place.latitude, place.longitude));
    } on ApiException catch (e) {
      if (!mounted || current != searchGeneration) return;
      setState(() {
        resolving = false;
        searchNote = e.code == 'PLACE_UNAVAILABLE' ? t('orderForm.addressNoCoordinates') : e.message;
      });
    }
  }

  void confirm() {
    final String text = address.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(PickedLocation(address: text, latitude: center.latitude, longitude: center.longitude));
  }

  @override
  Widget build(BuildContext context) {
    final double top = MediaQuery.paddingOf(context).top;
    final double bottom = MediaQuery.paddingOf(context).bottom;
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final bool canConfirm = !moving && !resolving && address.text.trim().isNotEmpty;
    return Scaffold(
      // Bàn phím không được đẩy bản đồ: bản đồ native đổi cỡ sẽ giật
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: AfterRouteEntrance(
              placeholder: ColoredBox(color: AppColors.background),
              child: VietmapGL(
                styleString: '${mapStyleUrl(false)}?apikey=${Env.vietmapKey}',
                initialCameraPosition: CameraPosition(target: center, zoom: widget.initial == null && widget.near == null ? 11 : 16),
                trackCameraPosition: true,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                compassEnabled: false,
                onMapCreated: (VietmapController created) => map = created,
                onCameraMove: onCameraMove,
                onCameraIdle: onCameraIdle,
              ),
            ),
          ),
          Center(child: IgnorePointer(child: _CenterPin(color: stopColor(widget.kind), number: widget.number, lifted: moving))),
          Positioned(
            left: 16,
            right: 16,
            top: top + 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    IosBackButton(size: 52, onPressed: () => Navigator.of(context).maybePop()),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Floating(
                        radius: 26,
                        child: CupertinoTextField(
                          controller: search,
                          focusNode: searchFocus,
                          placeholder: t('orderForm.mapSearchHint'),
                          placeholderStyle: TextStyle(fontSize: 16, color: IosColors.tertiaryLabel),
                          style: TextStyle(fontSize: 16, color: AppColors.text),
                          prefix: Padding(padding: const EdgeInsets.only(left: 14), child: Icon(CupertinoIcons.search, size: 20, color: IosColors.secondaryLabel)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
                          decoration: null,
                          autocorrect: false,
                          enableSuggestions: false,
                          clearButtonMode: OverlayVisibilityMode.editing,
                          textInputAction: TextInputAction.search,
                          onChanged: onSearchChanged,
                        ),
                      ),
                    ),
                  ],
                ),
                if (suggestions.isNotEmpty || searchNote != null) ...<Widget>[
                  const SizedBox(height: 8),
                  _Floating(
                    radius: 20,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.38),
                      child: searchNote != null
                          ? Padding(padding: const EdgeInsets.all(16), child: Text(searchNote!, style: TextStyle(fontSize: 14, color: AppColors.warnText)))
                          : ListView.separated(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                              itemCount: suggestions.length,
                              separatorBuilder: (BuildContext context, int index) => Container(height: 0.5, margin: const EdgeInsets.only(left: 16), color: IosColors.separator),
                              itemBuilder: (BuildContext context, int index) {
                                final AddressSuggestion item = suggestions[index];
                                return CupertinoButton(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                                  alignment: Alignment.centerLeft,
                                  onPressed: () => choose(item),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(item.name ?? item.display, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text)),
                                      if (item.name != null) Text(item.display, style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel)),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: keyboard,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                if (keyboard == 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 16, bottom: 12),
                    child: Semantics(
                      button: true,
                      label: t('orderForm.mapMyLocation'),
                      child: GestureDetector(
                        onTap: goToMe,
                        child: _Floating(
                          radius: 26,
                          child: SizedBox(width: 52, height: 52, child: Icon(CupertinoIcons.location_fill, size: 22, color: AppColors.navy)),
                        ),
                      ),
                    ),
                  ),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(20, 18, 20, keyboard > 0 ? 12 : bottom + 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x220C2858), blurRadius: 18, offset: Offset(0, -4))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(label(stopKindLabels, widget.kind), style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel)),
                          if (resolving) ...<Widget>[const SizedBox(width: 8), const CupertinoActivityIndicator(radius: 8)],
                        ],
                      ),
                      CupertinoTextField(
                        controller: address,
                        placeholder: t('orderForm.mapAddressHint'),
                        placeholderStyle: TextStyle(fontSize: 17, color: IosColors.tertiaryLabel),
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, height: 1.3, color: AppColors.text),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: null,
                        minLines: 1,
                        maxLines: 3,
                        autocorrect: false,
                        onChanged: (String _) => setState(() {}),
                      ),
                      if (addressFailed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(t('orderForm.mapAddressFailed'), style: TextStyle(fontSize: 13, height: 1.35, color: AppColors.warnText)),
                        ),
                      const SizedBox(height: 6),
                      SizedBox(height: 52, child: IosPillButton(label: t('orderForm.mapConfirm'), onPressed: canConfirm ? confirm : null)),
                      CupertinoButton(
                        padding: const EdgeInsets.only(top: 8),
                        minimumSize: const Size(44, 36),
                        onPressed: () => Navigator.of(context).pop(const PickedLocation.manual()),
                        child: Text(t('orderForm.mapManual'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: IosColors.blue)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Floating extends StatelessWidget {
  final double radius;
  final Widget child;

  const _Floating({required this.radius, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x290C2858), blurRadius: 14, offset: Offset(0, 4))],
      ),
      child: child,
    );
  }
}

/// Ghim đứng giữa màn, mũi ghim chỉ đúng tâm bản đồ; đang kéo thì nhấc lên
class _CenterPin extends StatelessWidget {
  final Color color;
  final int number;
  final bool lifted;

  const _CenterPin({required this.color, required this.number, required this.lifted});

  static const double height = 58;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -height / 2),
      child: SizedBox(
        height: height,
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: <Widget>[
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: lifted ? 8 : 14,
              height: lifted ? 4 : 6,
              decoration: BoxDecoration(color: const Color(0x550C2858), borderRadius: BorderRadius.circular(8)),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              bottom: lifted ? 12 : 2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x440C2858), blurRadius: 8, offset: Offset(0, 3))],
                    ),
                    child: Text('$number', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                  Container(width: 3, height: 12, color: color),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
