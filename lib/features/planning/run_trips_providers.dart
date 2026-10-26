// Hộp dữ liệu cho màn chuyến chạy và màn gán xe. autoDispose + family: mỗi đơn, mỗi chuyến một hộp riêng.
// Riverpod: FutureProvider, Ref
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'run_trips_api.dart';

final runTripsProvider = FutureProvider.autoDispose.family<List<RunTrip>, String>((Ref ref, String orderId) {
  return fetchRunTrips(orderId);
});

final candidatesProvider = FutureProvider.autoDispose.family<Candidates, String>((Ref ref, String tripId) {
  return fetchCandidates(tripId);
});
