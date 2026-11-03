import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/page_transition.dart';
import 'order_actions.dart' show orderFormSheetOpen;
import 'order_ai_screen.dart';
import 'order_detail_screen.dart';
import 'order_form.dart';
import 'order_map_screen.dart';
import 'order_new_screen.dart';
import 'orders_screen.dart';

// Các màn con khác của đơn (/orders/:orderId/plan, /dispatch-trips...) nằm ở planning/routes.dart, dispatch/routes.dart
final ordersRoutes = <RouteBase>[
  GoRoute(
    path: '/orders',
    builder: (BuildContext context, GoRouterState state) => const OrdersScreen(),
  ),
  // Phải đứng TRƯỚC /orders/:orderId, nếu không chữ "new" bị hiểu là mã đơn
  GoRoute(
    path: '/orders/new',
    builder: (BuildContext context, GoRouterState state) {
      final Object? cargos = state.extra;
      return OrderNewScreen(initialCargos: cargos is List<CargoDraft> ? cargos : const <CargoDraft>[]);
    },
  ),
  GoRoute(
    path: '/orders/new/ai',
    builder: (BuildContext context, GoRouterState state) => OrderAiScreen(thenOpenForm: state.uri.queryParameters['then'] == 'form'),
  ),
  GoRoute(
    path: '/orders/:orderId',
    builder: (BuildContext context, GoRouterState state) => NativeViewsPause(
      paused: orderFormSheetOpen,
      child: OrderDetailScreen(orderId: state.pathParameters['orderId']!),
    ),
  ),
  GoRoute(
    path: '/orders/:orderId/edit',
    builder: (BuildContext context, GoRouterState state) => OrderEditLoader(orderId: state.pathParameters['orderId']!),
  ),
  GoRoute(
    path: '/orders/:orderId/map',
    builder: (BuildContext context, GoRouterState state) => OrderMapScreen(orderId: state.pathParameters['orderId']!),
  ),
];
