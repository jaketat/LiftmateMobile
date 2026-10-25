// BuildContext (Flutter)
import 'package:flutter/widgets.dart';
// go_router: RouteBase, GoRoute, GoRouterState
import 'package:go_router/go_router.dart';

import 'customer_detail_screen.dart';
import 'customer_new_screen.dart';
import 'customers_screen.dart';

// Các màn khách hàng (người 4). router.dart gom vào bằng ...customersRoutes
final List<RouteBase> customersRoutes = <RouteBase>[
  // C1: danh sách khách
  GoRoute(
    path: '/customers',
    builder: (BuildContext context, GoRouterState state) {
      return const CustomersScreen();
    },
  ),
  // C3: thêm khách. Phải đứng TRƯỚC /customers/:customerId, nếu không chữ "new" bị hiểu là một id
  GoRoute(
    path: '/customers/new',
    builder: (BuildContext context, GoRouterState state) {
      return const CustomerNewScreen();
    },
  ),
  // C2: chi tiết khách
  GoRoute(
    path: '/customers/:customerId',
    builder: (BuildContext context, GoRouterState state) {
      return CustomerDetailScreen(customerId: state.pathParameters['customerId']!);
    },
  ),
];
