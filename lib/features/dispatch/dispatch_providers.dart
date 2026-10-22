// Hộp dữ liệu cho màn "Điều phối hôm nay". autoDispose: rời màn thì bỏ, mở lại thì gọi API lấy dữ liệu mới.
// Riverpod: FutureProvider, Ref
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dispatch_api.dart';

final FutureProvider<List<DispatchIssue>> dispatchIssuesProvider =
    FutureProvider.autoDispose<List<DispatchIssue>>((Ref ref) {
  return fetchDispatchIssues();
});

final FutureProvider<List<LiveTrip>> liveTripsProvider = FutureProvider.autoDispose<List<LiveTrip>>((Ref ref) {
  return fetchLiveTrips();
});

// family: mỗi chuyến (đơn + chuyến chạy) một hộp riêng
final tripTrackProvider = FutureProvider.autoDispose.family<TripTrack, TrackKey>((Ref ref, TrackKey key) {
  return fetchTripTrack(key);
});
