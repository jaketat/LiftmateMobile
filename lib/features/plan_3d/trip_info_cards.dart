// Các thẻ dưới hình 3D (bố cục giống trang kế hoạch trên web ở cỡ điện thoại):
// kết quả kiểm tra + cảnh báo, tải trục, kiện trên chuyến.
// Số do server tính sẵn (trip.layout.physics), app chỉ hiển thị.
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/labels.dart';
import '../../core/theme.dart';

// Khung trắng bo góc có tiêu đề, dùng chung cho các thẻ
class InfoCard extends StatelessWidget {
  final String? title;
  final Widget child;

  const InfoCard({super.key, this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[];
    if (title != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text(title!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      );
    }
    children.add(Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 14), child: child));

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

// Lấy chữ từ một cảnh báo / gợi ý: server trả {code, message} hoặc chuỗi
String messageOf(dynamic item) {
  if (item is Map<String, dynamic>) {
    return (item['message'] as String?) ?? '';
  }
  return item.toString();
}

// Thẻ kết quả: nhãn Đạt / Không đạt, các cảnh báo và gợi ý sửa của bố cục xếp
class TripCheckCard extends StatelessWidget {
  final Map<String, dynamic> trip;

  const TripCheckCard({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    final String verdict = (trip['verdict'] as String?) ?? 'Unchecked';
    final bool nearLimit = (trip['nearLimit'] as bool?) ?? false;
    final Map<String, dynamic>? layout = trip['layout'] as Map<String, dynamic>?;

    final List<Widget> children = <Widget>[
      Align(alignment: Alignment.centerLeft, child: VerdictChip(verdict: verdict, nearLimit: nearLimit)),
    ];
    final List<dynamic> warnings = (layout?['warnings'] as List<dynamic>?) ?? <dynamic>[];
    for (final dynamic warning in warnings) {
      children.add(MessageLine(icon: Icons.warning_amber_rounded, color: AppColors.warnText, text: messageOf(warning)));
    }
    final List<dynamic> fixHints = (layout?['fixHints'] as List<dynamic>?) ?? <dynamic>[];
    for (final dynamic hint in fixHints) {
      children.add(MessageLine(icon: Icons.lightbulb_outline, color: AppColors.navy, text: messageOf(hint)));
    }

    return InfoCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children));
  }
}

// Một dòng cảnh báo / gợi ý có biểu tượng đầu dòng
class MessageLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const MessageLine({super.key, required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, color: AppColors.label, height: 1.45))),
        ],
      ),
    );
  }
}

// Thẻ tải trục: tải từng cụm trục so với giới hạn trên giấy kiểm định, lực bám lái, chống lật
class AxleLoadCard extends StatefulWidget {
  final Map<String, dynamic> trip;

  const AxleLoadCard({super.key, required this.trip});

  @override
  State<AxleLoadCard> createState() {
    return _AxleLoadCardState();
  }
}

class _AxleLoadCardState extends State<AxleLoadCard> {
  // Chuyến nhiều điểm trả: mỗi điểm một trạng thái tải. Đang xem trạng thái thứ mấy
  int stateIndex = 0;

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? layout = widget.trip['layout'] as Map<String, dynamic>?;
    Map<String, dynamic>? physics;
    if (layout != null) {
      physics = layout['physics'] as Map<String, dynamic>?;
    }
    final List<dynamic> states = (physics?['states'] as List<dynamic>?) ?? <dynamic>[];

    if (states.isEmpty) {
      return const InfoCard(
        title: 'Tải trục',
        child: Text('Chưa kiểm tra tải trục: xe thiếu số liệu trục.', style: TextStyle(fontSize: 14, color: AppColors.warnText)),
      );
    }

    if (stateIndex >= states.length) {
      stateIndex = 0;
    }
    final Map<String, dynamic> state = states[stateIndex] as Map<String, dynamic>;
    final Map<String, dynamic>? beam = widget.trip['beam'] as Map<String, dynamic>?;
    Map<String, dynamic>? settings;
    if (beam != null) {
      settings = beam['settings'] as Map<String, dynamic>?;
    }

    final List<Widget> children = <Widget>[];

    // Nhiều điểm trả thì cho chọn xem tải sau điểm nào
    if (states.length > 1) {
      final List<Widget> chips = <Widget>[];
      for (int index = 0; index < states.length; index++) {
        final Map<String, dynamic> option = states[index] as Map<String, dynamic>;
        chips.add(
          ChoiceChip(
            label: Text('Sau điểm ${option['afterStop']}'),
            selected: index == stateIndex,
            onSelected: (bool selected) {
              setState(() {
                stateIndex = index;
              });
            },
          ),
        );
      }
      children.add(Wrap(spacing: 8, runSpacing: 4, children: chips));
      children.add(const SizedBox(height: 8));
    }

    // Bảng: cụm trục | tải | cho phép | còn dư
    final List<TableRow> rows = <TableRow>[
      const TableRow(
        children: [
          HeaderCell('Cụm trục'),
          HeaderCell('Tải', alignEnd: true),
          HeaderCell('Cho phép', alignEnd: true),
          HeaderCell('Còn dư', alignEnd: true),
        ],
      ),
    ];
    for (final dynamic row in (state['supports'] as List<dynamic>?) ?? <dynamic>[]) {
      final Map<String, dynamic> support = row as Map<String, dynamic>;
      final num total = support['totalKg'] as num;
      final num? limit = support['limitKg'] as num?;
      final num? reserve = support['reserveKg'] as num?;
      // Vượt giới hạn thì tô đỏ cả dòng
      final bool isOver = limit != null && total > limit;

      String limitText = 'không giới hạn';
      if (limit != null) {
        limitText = formatKg(limit.round());
      }
      String reserveText = '—';
      if (reserve != null) {
        reserveText = formatKg(reserve.round());
      }

      rows.add(
        TableRow(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
          children: [
            BodyCell(support['name'] as String, isOver: isOver),
            BodyCell(formatKg(total.round()), isOver: isOver, alignEnd: true),
            BodyCell(limitText, isOver: isOver, alignEnd: true),
            BodyCell(reserveText, isOver: isOver, alignEnd: true),
          ],
        ),
      );
    }
    children.add(
      Table(
        // Cột tên rộng gấp đôi các cột số
        columnWidths: const <int, TableColumnWidth>{0: FlexColumnWidth(2)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: rows,
      ),
    );

    // Lực bám lái: xe thường dùng steeringShare, đầu kéo dùng tractorSteeringShare
    num? steering = state['steeringShare'] as num?;
    steering ??= state['tractorSteeringShare'] as num?;
    if (steering != null) {
      final num? minimum = settings?['minSteeringShare'] as num?;
      children.add(
        RatioLine(
          text: 'Cầu trước gánh ${(steering * 100).round()}% tổng tải (lực bám lái)',
          minimumText: minimum == null ? null : 'tối thiểu ${(minimum * 100).round()}%',
          isBad: minimum != null && steering < minimum,
        ),
      );
    }
    final num? rollover = state['rolloverRatio'] as num?;
    if (rollover != null) {
      final num? minimum = settings?['minRolloverRatio'] as num?;
      children.add(
        RatioLine(
          text: 'Hệ số chống lật ${rollover.toStringAsFixed(2).replaceAll('.', ',')}',
          minimumText: minimum == null ? null : 'tối thiểu ${minimum.toStringAsFixed(2).replaceAll('.', ',')}',
          isBad: minimum != null && rollover < minimum,
        ),
      );
    }
    children.add(
      const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'Giới hạn lấy theo giấy kiểm định của xe. Số do máy chủ tính, đã cộng xe không tải.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      ),
    );

    return InfoCard(
      title: 'Tải trục',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

// Thẻ kiện trên chuyến: mã kiện, tên, số lượng
class TripItemsCard extends StatelessWidget {
  final Map<String, dynamic> trip;

  const TripItemsCard({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    final List<dynamic> items = (trip['items'] as List<dynamic>?) ?? <dynamic>[];
    num totalQuantity = 0;
    final List<Widget> rows = <Widget>[];
    for (int index = 0; index < items.length; index++) {
      final Map<String, dynamic> item = items[index] as Map<String, dynamic>;
      final num quantity = (item['quantity'] as num?) ?? 0;
      totalQuantity = totalQuantity + quantity;
      if (index > 0) {
        rows.add(const Divider(height: 1, color: AppColors.border));
      }
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Text('${item['cargoCode'] ?? ''}  ', style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
              Expanded(child: Text('${item['cargoName'] ?? ''}', style: const TextStyle(fontSize: 14))),
              Text('× ${formatNumber(quantity)}', style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
      );
    }
    return InfoCard(
      title: 'Kiện trên chuyến (${formatNumber(totalQuantity)})',
      child: Column(children: rows),
    );
  }
}

// Nhãn Đạt (xanh) / Không đạt (đỏ) / Chưa kiểm được (vàng), thêm "gần giới hạn" nếu có
class VerdictChip extends StatelessWidget {
  final String verdict;
  final bool nearLimit;

  const VerdictChip({super.key, required this.verdict, required this.nearLimit});

  @override
  Widget build(BuildContext context) {
    Color background = AppColors.warnBackground;
    Color foreground = AppColors.warnText;
    if (verdict == 'Pass') {
      background = AppColors.okBackground;
      foreground = AppColors.okText;
    } else if (verdict == 'Fail') {
      background = AppColors.errorBackground;
      foreground = AppColors.errorText;
    }
    String text = label(verdictLabels, verdict);
    if (nearLimit && verdict == 'Pass') {
      text = '$text · gần giới hạn';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Text('●  $text', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: foreground)),
    );
  }
}

// Ô tiêu đề cột của bảng
class HeaderCell extends StatelessWidget {
  final String text;
  final bool alignEnd;

  const HeaderCell(this.text, {super.key, this.alignEnd = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
      ),
    );
  }
}

// Ô số liệu của bảng, đỏ đậm khi vượt giới hạn
class BodyCell extends StatelessWidget {
  final String text;
  final bool isOver;
  final bool alignEnd;

  const BodyCell(this.text, {super.key, required this.isOver, this.alignEnd = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        style: TextStyle(
          fontSize: 13,
          color: isOver ? AppColors.errorText : AppColors.text,
          fontWeight: isOver ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );
  }
}

// Một dòng chỉ số kèm mức tối thiểu, dưới mức thì đỏ
class RatioLine extends StatelessWidget {
  final String text;
  final String? minimumText;
  final bool isBad;

  const RatioLine({super.key, required this.text, required this.minimumText, required this.isBad});

  @override
  Widget build(BuildContext context) {
    String fullText = text;
    if (minimumText != null) {
      fullText = '$text · $minimumText';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(
            isBad ? Icons.error_outline : Icons.check_circle_outline,
            size: 18,
            color: isBad ? AppColors.errorText : AppColors.okText,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              fullText,
              style: TextStyle(fontSize: 13, color: isBad ? AppColors.errorText : AppColors.label),
            ),
          ),
        ],
      ),
    );
  }
}
