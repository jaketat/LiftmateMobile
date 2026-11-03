// N8: xem 3D một chuyến trong WebView (doc mục 3.9, màn N1-Xem3D).
// App lấy dữ liệu chuyến, mở trang {WEB_BASE}/embed/xep-hang-3d, chờ trang báo "ready" rồi gửi dữ liệu vào.
// Trang không gọi API: KHÔNG BAO GIỜ đưa token vào WebView.
import 'dart:async';
import 'dart:convert';

// Factory: tạo bộ nhận cử chạm cho WebView
import 'package:flutter/foundation.dart';
// EagerGestureRecognizer, OneSequenceGestureRecognizer
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.pushReplacement
import 'package:go_router/go_router.dart';
// webview_flutter (thư viện ngoài): khung hiện trang web bên trong app
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/env.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/page_transition.dart';
import 'trip_info_cards.dart';
import 'plan_3d_api.dart';
import 'plan_3d_providers.dart';

class Trip3DScreen extends ConsumerWidget {
  final TripKey tripKey;

  const Trip3DScreen({super.key, required this.tripKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Trip3DData> dataValue = ref.watch(trip3DProvider(tripKey));

    String title = t('plan3d.trip.title');
    String subtitle = '';
    if (dataValue.hasValue) {
      final Trip3DData data = dataValue.value!;
      title = t('plan3d.trip.titleWithSequence', <String, Object?>{'sequence': data.trip['sequence']});
      subtitle = t('plan3d.vehicle', <String, Object?>{'plate': data.plateNumber});
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            if (subtitle.isNotEmpty)
              Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: t('plan3d.view2d'),
            icon: const Icon(Icons.grid_on),
            onPressed: () {
              openBlueprint(context, tripKey);
            },
          ),
        ],
      ),
      body: AsyncView<Trip3DData>(
        value: dataValue,
        onRetry: () {
          ref.invalidate(trip3DProvider(tripKey));
        },
        builder: (Trip3DData data) {
          // Cuộn dọc như trang kế hoạch trên web ở cỡ điện thoại: 3D ở trên, các thẻ ở dưới
          return ListView(
            padding: withTabBarInset(context, const EdgeInsets.only(bottom: 16)),
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
                child: Trip3DView(tripKey: tripKey, data: data),
              ),
              TripCheckCard(trip: data.trip),
              AxleLoadCard(trip: data.trip),
              TripItemsCard(trip: data.trip),
            ],
          );
        },
      ),
    );
  }
}

// Thay màn 3D bằng màn 2D cùng chuyến
void openBlueprint(BuildContext context, TripKey tripKey) {
  context.pushReplacement('/orders/${tripKey.orderId}/plans/${tripKey.planId}/trips/${tripKey.tripId}/2d');
}

// Khung WebView. StatefulWidget vì phải giữ controller của WebView suốt lúc màn mở
class Trip3DView extends StatefulWidget {
  final TripKey tripKey;
  final Trip3DData data;

  const Trip3DView({super.key, required this.tripKey, required this.data});

  @override
  State<Trip3DView> createState() {
    return _Trip3DViewState();
  }
}

class _Trip3DViewState extends State<Trip3DView> {
  // WebViewController (webview_flutter): điều khiển trang web: mở địa chỉ, chạy JavaScript, nhận tin nhắn
  late final WebViewController controller;
  // Trang báo lỗi hoặc không tải được thì có câu lỗi
  String? errorText;
  // Hẹn giờ: quá 20 giây trang không báo "ready" thì coi là lỗi (trang chưa Deploy, mạng chậm)
  Timer? readyTimer;

  @override
  void initState() {
    super.initState();

    controller = WebViewController();
    // Trang 3D cần JavaScript để vẽ
    controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    // Kênh LiftmateApp: trang gửi tin nhắn cho app qua window.LiftmateApp.postMessage(...)
    controller.addJavaScriptChannel('LiftmateApp', onMessageReceived: onPageMessage);
    controller.setNavigationDelegate(
      NavigationDelegate(
        // Chỉ cho mở trang của LiftMate, chặn bấm link sang trang lạ
        onNavigationRequest: (NavigationRequest request) {
          if (request.url.startsWith(Env.webBase)) {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
        // Không tải được trang chính (mất mạng, sai địa chỉ)
        onWebResourceError: (WebResourceError error) {
          if (error.isForMainFrame == true) {
            showError(t('plan3d.trip.openFailed'));
          }
        },
      ),
    );
    controller.loadRequest(Uri.parse('${Env.webBase}/embed/xep-hang-3d'));

    readyTimer = Timer(const Duration(seconds: 20), () {
      showError(t('plan3d.trip.noResponse'));
    });
  }

  @override
  void dispose() {
    readyTimer?.cancel();
    super.dispose();
  }

  void showError(String message) {
    readyTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      errorText = message;
    });
  }

  // Trang gửi {"type":"ready"} hoặc {"type":"error","message":"..."}
  void onPageMessage(JavaScriptMessage message) {
    final Map<String, dynamic> pageMessage = jsonDecode(message.message) as Map<String, dynamic>;
    if (pageMessage['type'] == 'ready') {
      readyTimer?.cancel();
      // Gửi dữ liệu chuyến cho trang vẽ. jsonEncode cho ra chuỗi JSON, cũng là cú pháp JavaScript hợp lệ
      final String payload = jsonEncode(<String, dynamic>{
        'trip': widget.data.trip,
        'cargos': widget.data.cargos,
      });
      controller.runJavaScript('window.liftmate3d.render($payload)');
    } else if (pageMessage['type'] == 'error') {
      showError((pageMessage['message'] as String?) ?? t('plan3d.trip.dataError'));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (errorText != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(errorText!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  openBlueprint(context, widget.tripKey);
                },
                child: Text(t('plan3d.view2d')),
              ),
            ],
          ),
        ),
      );
    }
    // WebViewWidget (webview_flutter): vẽ trang web.
    // EagerGestureRecognizer (Flutter): chạm trong khung 3D thì WebView nhận (xoay, phóng to),
    // không bị trang cuộn bên ngoài giành mất. Muốn cuộn trang thì vuốt ở phần thẻ bên dưới.
    return WebViewWidget(
      controller: controller,
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(() {
          return EagerGestureRecognizer();
        }),
      },
    );
  }
}
