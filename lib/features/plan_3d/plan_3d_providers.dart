// Hộp dữ liệu cho màn 2D và 3D. family: mỗi chuyến (bộ 3 id) một hộp riêng.
// Riverpod: FutureProvider, Ref
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'plan_3d_api.dart';

final blueprintProvider = FutureProvider.autoDispose.family<TripBlueprint, TripKey>((Ref ref, TripKey key) {
  return fetchBlueprint(key);
});

final trip3DProvider = FutureProvider.autoDispose.family<Trip3DData, TripKey>((Ref ref, TripKey key) {
  return fetchTrip3DData(key);
});
