// K3: tiền dầu khứ hồi của kế hoạch (theo màn N3-TienDau trên canvas)
import 'package:flutter/material.dart';
// Riverpod: ConsumerWidget, WidgetRef, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import 'planning_api.dart';
import 'planning_providers.dart';

class CostEstimateScreen extends ConsumerWidget {
  final PlanKey planKey;

  const CostEstimateScreen({super.key, required this.planKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<CostEstimate> costValue = ref.watch(costEstimateProvider(planKey));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tiền dầu khứ hồi', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: AsyncView<CostEstimate>(
        value: costValue,
        onRetry: () {
          ref.invalidate(costEstimateProvider(planKey));
        },
        isEmpty: (CostEstimate cost) {
          return cost.trips.isEmpty;
        },
        emptyText: 'Kế hoạch chưa có chuyến nào để tính tiền dầu.',
        builder: (CostEstimate cost) {
          final List<Widget> children = <Widget>[
            _TotalPanel(cost: cost),
            const SizedBox(height: 10),
            _PriceBox(cost: cost),
          ];

          // Hết lượt bản đồ: có chuyến thiếu phí BOT
          if (cost.incomplete) {
            children.add(const SizedBox(height: 10));
            children.add(
              const _NoteBox(
                text: 'Chưa đủ phí BOT: một số chuyến chưa tính được phí cầu đường.',
                background: AppColors.warnBackground,
                foreground: AppColors.warnText,
              ),
            );
          }

          for (final TripCost trip in cost.trips) {
            children.add(const SizedBox(height: 10));
            children.add(_TripCostCard(trip: trip));
          }

          children.add(const SizedBox(height: 14));
          children.add(
            const Text(
              'Chiều về tính bằng chiều đi. Chỉ để tham khảo nội bộ, không cộng vào giá báo khách.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          );

          // Kéo xuống để tải lại
          return RefreshIndicator(
            onRefresh: () {
              return ref.refresh(costEstimateProvider(planKey).future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: children,
            ),
          );
        },
      ),
    );
  }
}

// Khung xanh đậm: tổng khứ hồi, dầu, BOT
class _TotalPanel extends StatelessWidget {
  final CostEstimate cost;

  const _TotalPanel({required this.cost});

  @override
  Widget build(BuildContext context) {
    const Color muted = Color(0xFFC9D2E3);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tổng khứ hồi · ${cost.trips.length} chuyến', style: const TextStyle(fontSize: 13, color: muted)),
          const SizedBox(height: 8),
          Text(
            formatMoney(cost.total),
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 20,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Dầu ', style: TextStyle(color: muted)),
                    TextSpan(text: formatMoney(cost.fuelTotal)),
                  ],
                ),
                style: const TextStyle(fontSize: 14, color: Colors.white),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'BOT ', style: TextStyle(color: muted)),
                    TextSpan(text: formatMoney(cost.tollTotal)),
                  ],
                ),
                style: const TextStyle(fontSize: 14, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Giá dầu đang dùng để tính
class _PriceBox extends StatelessWidget {
  final CostEstimate cost;

  const _PriceBox({required this.cost});

  @override
  Widget build(BuildContext context) {
    String text = 'Giá dầu DO Petrolimex ${formatNumber(cost.pricePerLiter)} đ/lít';
    if (cost.priceEffectiveDate != null) {
      text = '$text, áp dụng từ ${formatDate(cost.priceEffectiveDate)}';
    }
    text = '$text. Máy chủ tự cập nhật 6 giờ một lần.';
    if (cost.priceStale) {
      text = '$text Giá có thể đã cũ.';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_gas_station_outlined, size: 22, color: Color(0xFFB4541A)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: AppColors.label, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

// Ô ghi chú màu (vàng hoặc đỏ nhạt)
class _NoteBox extends StatelessWidget {
  final String text;
  final Color background;
  final Color foreground;

  const _NoteBox({required this.text, required this.background, required this.foreground});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(fontSize: 12, color: foreground)),
    );
  }
}

// Một chuyến: tiêu đề + tổng, rồi quãng đường, dầu, BOT
class _TripCostCard extends StatelessWidget {
  final TripCost trip;

  const _TripCostCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    // vehicleLabel có thể đã có chữ "Chuyến N · ..." sẵn
    String title = 'Chuyến ${trip.sequence}';
    if (trip.vehicleLabel.isNotEmpty) {
      if (trip.vehicleLabel.startsWith('Chuyến')) {
        title = trip.vehicleLabel;
      } else {
        title = '$title · ${trip.vehicleLabel}';
      }
    }

    String distance = '${formatNumber(trip.distanceKm)} km';
    if (trip.distanceApproximate) {
      distance = 'khoảng $distance';
    }

    String defaultNote = trip.note;
    if (defaultNote.isEmpty) {
      defaultNote = 'Xe chưa khai mức tiêu hao dầu, đang dùng mức mặc định.';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
              const SizedBox(width: 8),
              Text(
                formatMoney(trip.roundTripTotal),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _MutedRow(title: 'Quãng đường một chiều', value: distance),
          _MutedRow(title: 'Dầu khứ hồi', value: formatMoney(trip.fuelRoundTrip)),
          _MutedRow(title: 'BOT khứ hồi', value: formatMoney(trip.tollRoundTrip)),
          if (trip.usedDefaultConsumption)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _NoteBox(
                text: defaultNote,
                background: AppColors.warnBackground,
                foreground: AppColors.warnText,
              ),
            ),
        ],
      ),
    );
  }
}

class _MutedRow extends StatelessWidget {
  final String title;
  final String value;

  const _MutedRow({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    const TextStyle style = TextStyle(fontSize: 14, color: AppColors.textMuted);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(title, style: style)),
          const SizedBox(width: 12),
          Text(value, style: style),
        ],
      ),
    );
  }
}
