// Bản đồ tuyến của đơn, toàn màn. Tách khỏi màn chi tiết: bản đồ nằm trong danh sách cuộn sẽ làm cuộn lệch nhịp.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vietmap_flutter_gl/vietmap_flutter_gl.dart' show LatLng;

import '../../core/i18n.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/ios.dart';
import '../driver/directions_logic.dart';
import '../driver/driver_api.dart' show TripStop;
import '../driver/trip_map.dart';
import 'orders_api.dart';

/// Bản đồ tuyến toàn màn: nút quay lại, tên, nút đổi kiểu bản đồ
class RouteMapPage extends StatelessWidget {
  final String title;
  final List<TripStop> stops;
  final List<LatLng>? route;

  const RouteMapPage({super.key, required this.title, required this.stops, this.route});

  @override
  Widget build(BuildContext context) {
    final double top = MediaQuery.paddingOf(context).top;
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: TripMap(
            stops: stops,
            route: route,
            // Nội dung chạy xuống dưới thanh tab kính, chừa chỗ để điểm dừng không bị che
            fitPadding: EdgeInsets.fromLTRB(48, top + 90, 48, MediaQuery.paddingOf(context).bottom + 110),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          top: top + 12,
          child: Row(
            children: <Widget>[
              IosBackButton(size: 52, onPressed: () => Navigator.of(context).maybePop()),
              const SizedBox(width: 10),
              Expanded(
                child: Glass(
                  nativeSurface: true,
                  borderRadius: BorderRadius.circular(26),
                  opacity: 0.66,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                  child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Semantics(label: t('orderDetail.viewMap'), child: const MapStyleButton(size: 52)),
            ],
          ),
        ),
      ],
    );
  }
}

class OrderMapScreen extends ConsumerWidget {
  final String orderId;

  const OrderMapScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: AsyncView<OrderDetail>(
        value: ref.watch(orderDetailProvider(orderId)),
        onRetry: () => ref.invalidate(orderDetailProvider(orderId)),
        builder: (OrderDetail order) {
          final String polyline = order.routePolyline ?? '';
          return RouteMapPage(
            title: order.orderCode,
            stops: <TripStop>[
              for (final OrderStop stop in order.stops)
                TripStop(
                  sequence: stop.sequence,
                  kind: stop.kind,
                  address: stop.address,
                  latitude: stop.latitude,
                  longitude: stop.longitude,
                  contactName: stop.contactName,
                  contactPhone: stop.contactPhone,
                  note: stop.note,
                ),
            ],
            route: polyline.isEmpty ? null : decodePolyline(polyline),
          );
        },
      ),
    );
  }
}
