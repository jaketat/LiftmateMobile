// Luật thuần (không gọi API, không vẽ) của app tài xế: chữ nút mốc, thứ tự mốc trong một điểm,
// chia chuyến thành Hôm nay / Sắp tới / Đã qua. Tách riêng để viết test dễ.
import 'driver_api.dart';
import '../../core/i18n.dart';

/// Thứ tự mốc trong một điểm (doc slice D mục 2):
/// bốc Arrived → Loaded → Departed; trả Arrived → Unloaded → Departed; đi qua Arrived → Departed.
List<String> stepsForStop(String stopKind) {
  switch (stopKind) {
    case 'Pickup':
      return const <String>['Arrived', 'Loaded', 'Departed'];
    case 'Delivery':
      return const <String>['Arrived', 'Unloaded', 'Departed'];
    default:
      return const <String>['Arrived', 'Departed'];
  }
}

/// Chữ trên nút / dòng mốc, theo loại mốc và loại điểm.
String milestoneActionLabel(String kind, String stopKind) {
  switch (kind) {
    case 'Arrived':
      if (stopKind == 'Pickup') return t('trip.action.arrivedPickup');
      if (stopKind == 'Delivery') return t('trip.action.arrivedDelivery');
      return t('trip.action.arrivedVia');
    case 'Loaded':
      return t('trip.action.loaded');
    case 'Unloaded':
      return t('trip.action.unloaded');
    case 'Departed':
      return stopKind == 'Pickup' ? t('trip.action.start') : t('trip.action.depart');
    default:
      return kind;
  }
}

String stopKindTitle(String stopKind) {
  return tEnum('stopKind', stopKind == 'Pickup' || stopKind == 'Delivery' ? stopKind : 'Via').toUpperCase();
}

/// Mốc kế tiếp chưa bấm của một điểm; null khi điểm đã xong.
String? nextStepAtStop(MyTrip trip, TripStop stop) {
  final Set<String> done = trip.milestonesAt(stop.sequence).map((TripMilestone m) => m.kind).toSet();
  for (final String step in stepsForStop(stop.kind)) {
    if (!done.contains(step)) {
      return step;
    }
  }
  return null;
}

/// Mốc đã bấm của điểm theo loại (null: chưa bấm)
TripMilestone? milestoneOf(MyTrip trip, int stopSequence, String kind) {
  TripMilestone? found;
  for (final TripMilestone milestone in trip.milestonesAt(stopSequence)) {
    if (milestone.kind == kind) {
      found = milestone;
    }
  }
  return found;
}

/// Chữ cho dòng mốc đã xong (giống web: "Đã tới 07:52", "Bắt đầu chạy 08:10")
String milestoneDoneLabel(String kind, String stopKind) {
  switch (kind) {
    case 'Arrived':
      return t('trip.done.arrived');
    case 'Loaded':
      return t('trip.done.loaded');
    case 'Unloaded':
      return t('trip.done.unloaded');
    case 'Departed':
      return stopKind == 'Pickup' ? t('trip.done.started') : t('trip.done.departed');
    default:
      return kind;
  }
}

enum StopState { todo, active, done }

/// Điểm có Departed là xong; có mốc mà chưa Departed là đang ở đó
StopState stopState(MyTrip trip, TripStop stop) {
  final List<TripMilestone> mine = trip.milestonesAt(stop.sequence);
  if (mine.any((TripMilestone m) => m.kind == 'Departed')) return StopState.done;
  return mine.isEmpty ? StopState.todo : StopState.active;
}

/// Ô đồng hồ khi rời điểm trả CUỐI (BR-TRK-009, giống web meterFields): chỉ lái chính, xe mình lái;
/// km cho xe chạy đường, giờ máy cho cẩu / xe nâng. null: không hỏi.
({bool km, bool hours})? meterFields(MyTrip trip) {
  final NextAction? next = trip.nextAction;
  if (next == null || next.kind != 'Departed' || !trip.isMainDriver) return null;
  final TripStop? stop = trip.stopAt(next.stopSequence);
  if (stop == null || stop.kind != 'Delivery') return null;
  for (final TripStop other in trip.stops) {
    if (other.kind == 'Delivery' && other.sequence != stop.sequence && stopState(trip, other) != StopState.done) {
      return null;
    }
  }
  TripVehicle? vehicle;
  for (final TripVehicle v in trip.vehicles) {
    if (v.publicId == trip.myVehiclePublicId) vehicle = v;
  }
  if (vehicle == null) return null;
  final bool km = vehicleHasOdometer(vehicle.baseType);
  final bool hours = vehicleHasEngineHours(vehicle.baseType);
  if (!km && !hours) return null;
  return (km: km, hours: hours);
}

/// Các điểm khác chưa làm gì (để "Đến điểm khác?" khi khách đổi thứ tự)
List<TripStop> skippableStops(MyTrip trip) {
  final int? current = trip.nextAction?.stopSequence;
  return trip.stops.where((TripStop s) => s.sequence != current && stopState(trip, s) == StopState.todo).toList();
}

/// Mốc hoàn tác được (server chỉ cho mốc cuối của điểm, mình bấm, chưa quá 5 phút)
TripMilestone? undoableMilestone(MyTrip trip) {
  for (final TripMilestone milestone in trip.milestones) {
    if (milestone.canUndo) return milestone;
  }
  return null;
}

/// Xe tải, đầu kéo, cẩu bánh lốp có đồng hồ km
bool vehicleHasOdometer(String? baseType) {
  return baseType == 'Truck' || baseType == 'TractorHead' || baseType == 'MobileCraneWheeled';
}

/// Cẩu, xe nâng có đồng hồ giờ máy
bool vehicleHasEngineHours(String? baseType) {
  return baseType == 'MobileCraneWheeled' || baseType == 'MobileCraneCrawler' || baseType == 'Forklift';
}

/// Câu thay nút bấm mốc khi chưa bấm được. Server chỉ mở bấm mốc khi đơn ở Đã chốt lịch,
/// Đang thực hiện hoặc Chờ chốt phát sinh VÀ đang trong khung chuyến nới 12 tiếng hai đầu (BR-TRK).
String? milestoneBlockedText(MyTrip trip, DateTime now) {
  if (!trip.trackingActive) {
    switch (trip.orderStatus) {
      case 'Draft':
      case 'Quoted':
      case 'CustomerConfirmed':
        return t('trip.blocked.notScheduled');
      case 'Cancelled':
        return t('trip.blocked.cancelled');
      case 'Finalized':
      case 'Invoiced':
        return t('trip.blocked.closed');
    }
    if (trip.startAt.subtract(const Duration(hours: 12)).isAfter(now)) {
      // Mở bấm mốc trước giờ chạy 12 tiếng
      final DateTime opens = trip.startAt.subtract(const Duration(hours: 12));
      return t('trip.blocked.tooEarly', <String, Object?>{'time': '${clock(opens)} ${_two(opens.toLocal().day)}/${_two(opens.toLocal().month)}'});
    }
    if (trip.endAt.add(const Duration(hours: 12)).isBefore(now)) {
      return t('trip.blocked.ended');
    }
    return t('trip.blocked.other');
  }
  if (trip.nextAction == null) {
    return t('trip.allStopsDone');
  }
  return null;
}

/// Hoàn tác "Bắt đầu chạy" không đưa đơn về Đã chốt lịch: hộp xác nhận phải nói rõ.
bool undoKeepsOrderInProgress(MyTrip trip, TripMilestone milestone) {
  if (milestone.kind != 'Departed') {
    return false;
  }
  final TripStop? stop = trip.stopAt(milestone.stopSequence);
  return stop != null && stop.kind == 'Pickup';
}

class TripGroups {
  final List<MyTrip> today;
  final List<MyTrip> upcoming;
  final List<MyTrip> past;

  const TripGroups({required this.today, required this.upcoming, required this.past});

  int get total => today.length + upcoming.length + past.length;
}

DateTime _dayOf(DateTime moment) {
  final DateTime local = moment.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Chia chuyến: Hôm nay (bắt đầu hôm nay, hoặc đang trong khung giờ, hoặc còn việc mà đã bắt đầu),
/// Sắp tới (bắt đầu từ mai), Đã qua (còn lại). Hôm nay và Sắp tới xếp tăng dần, Đã qua mới nhất trước.
TripGroups groupTrips(List<MyTrip> trips, DateTime now) {
  final DateTime today = _dayOf(now);
  final List<MyTrip> todayTrips = <MyTrip>[];
  final List<MyTrip> upcoming = <MyTrip>[];
  final List<MyTrip> past = <MyTrip>[];

  for (final MyTrip trip in trips) {
    final DateTime startDay = _dayOf(trip.startAt);
    final bool running = !trip.startAt.isAfter(now) && !trip.endAt.isBefore(now);
    final bool unfinishedStarted = !trip.startAt.isAfter(now) && trip.trackingActive && trip.nextAction != null;
    if (startDay == today || running || unfinishedStarted) {
      todayTrips.add(trip);
    } else if (startDay.isAfter(today)) {
      upcoming.add(trip);
    } else {
      past.add(trip);
    }
  }

  int byStart(MyTrip a, MyTrip b) => a.startAt.compareTo(b.startAt);
  todayTrips.sort(byStart);
  upcoming.sort(byStart);
  past.sort((MyTrip a, MyTrip b) => b.startAt.compareTo(a.startAt));
  return TripGroups(today: todayTrips, upcoming: upcoming, past: past);
}

/// Chuyến nổi bật trên sheet thu gọn và trên bản đồ trang chủ:
/// chuyến hôm nay còn việc → chuyến hôm nay đầu tiên → chuyến sắp tới gần nhất.
MyTrip? featuredTrip(TripGroups groups) {
  for (final MyTrip trip in groups.today) {
    if (trip.nextAction != null && trip.trackingActive) {
      return trip;
    }
  }
  if (groups.today.isNotEmpty) {
    return groups.today.first;
  }
  if (groups.upcoming.isNotEmpty) {
    return groups.upcoming.first;
  }
  return null;
}

/// Câu "Tiếp theo: ..." của một chuyến; null khi không có gì để bấm.
String? nextActionText(MyTrip trip) {
  final NextAction? next = trip.nextAction;
  if (next == null) {
    return trip.milestones.isEmpty ? null : t('trip.allStopsDone');
  }
  final TripStop? stop = trip.stopAt(next.stopSequence);
  return t('trip.next', <String, Object?>{'action': milestoneActionLabel(next.kind, stop?.kind ?? 'Via')});
}

// Thứ trong tuần theo ngôn ngữ máy (1 = Thứ Hai … 7 = Chủ Nhật, như DateTime.weekday)
String _weekday(int weekday) => t('ui.weekday.$weekday');
String _weekdayShort(int weekday) => t('ui.weekdayShort.$weekday');

String _two(int value) => value.toString().padLeft(2, '0');

/// "Thứ Hai, 26/10/2026"
String longDate(DateTime moment) {
  final DateTime local = moment.toLocal();
  return '${_weekday(local.weekday)}, ${_two(local.day)}/${_two(local.month)}/${local.year}';
}

/// "08:00"
String clock(DateTime moment) {
  final DateTime local = moment.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)}';
}

/// "08:00 – 12:00", khác ngày thì "T7 31/10 · 07:00 – 16:00"
String tripTimeText(MyTrip trip, {bool withDay = false}) {
  final String range = '${clock(trip.startAt)} – ${clock(trip.endAt)}';
  if (!withDay) {
    return range;
  }
  final DateTime start = trip.startAt.toLocal();
  return '${_weekdayShort(start.weekday)} ${_two(start.day)}/${_two(start.month)} · $range';
}
