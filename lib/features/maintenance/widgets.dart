// Widget dùng chung cho 9 màn bảo hồng - bảo trì.
// Chỉ phần này dùng nên để cùng thư mục; nếu sau này người khác cũng cần thì báo người 1
// để chuyển lên core/widgets/ cho cả nhóm dùng chung.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// Riverpod: AsyncValue - PagedListView nhận trạng thái của hộp dữ liệu
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/paged_result.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/page_transition.dart';

// ------------------------------------------------------------- Khung chung

/// Thẻ trắng bo góc, dùng làm khối chính trong màn.
class SectionCard extends StatelessWidget {
  final List<Widget> children;
  // Viền và nền khác mặc định, vd khung cảnh báo đỏ cho lịch quá hạn
  final Color? borderColor;
  final Color? background;
  final EdgeInsets padding;

  const SectionCard({
    super.key,
    required this.children,
    this.borderColor,
    this.background,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? AppColors.surface,
        border: Border.all(color: borderColor ?? AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

/// Tiêu đề một khối trong thẻ, đậm hơn chữ thường.
class SectionHeading extends StatelessWidget {
  final String text;

  const SectionHeading(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text),
    );
  }
}

/// Nhãn nhỏ phía trên ô nhập.
class FieldLabel extends StatelessWidget {
  final String text;
  final String? hint;

  const FieldLabel(this.text, {super.key, this.hint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.label)),
          if (hint != null) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text(hint!, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Một dòng "nhãn: giá trị" trong thẻ chi tiết, vd "Xe  51D-900.02 · đầu kéo".
class DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Widget? trailing;

  const DetailRow({
    super.key,
    required this.label,
    required this.value,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 92, child: Text(label, style: TextStyle(fontSize: 14, color: AppColors.textMuted))),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 14, color: AppColors.text, fontWeight: FontWeight.w500),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Ghi chú nhỏ dưới màn, chữ nhỏ màu phụ.
class NoteText extends StatelessWidget {
  final String text;
  final Color color;

  NoteText(this.text, {super.key, Color? color}) : color = color ?? AppColors.textMuted;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: 12, height: 1.4, color: color),
    );
  }
}

/// Khung cảnh báo vàng: vẫn cho lưu, chỉ báo trước.
class WarnBox extends StatelessWidget {
  final String title;
  final String message;
  final List<Widget> children;

  const WarnBox({
    super.key,
    required this.title,
    required this.message,
    this.children = const <Widget>[],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warnBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.warnText)),
          const SizedBox(height: 4),
          Text(message, style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.warnText)),
          for (final Widget child in children) ...[
            const SizedBox(height: 10),
            child,
          ],
        ],
      ),
    );
  }
}

/// Khung lỗi đỏ hiện trong form (không phải SnackBar): để câu lỗi nằm nguyên trong màn.
class ErrorBox extends StatelessWidget {
  final String text;

  const ErrorBox(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: AppColors.errorBackground, borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: TextStyle(fontSize: 14, color: AppColors.errorText)),
    );
  }
}

// ------------------------------------------------------------------ Nhãn

/// Nhãn nhỏ bo tròn màu, dùng cho trạng thái bảo hồng, mức độ, loại lịch.
/// Màu chọn theo `tone` thay vì theo tên hằng, để không lệ thuộc giá trị cụ thể của server.
class ToneChip extends StatelessWidget {
  final String text;
  final Tone tone;
  final bool isFilled;

  const ToneChip(this.text, {super.key, required this.tone, this.isFilled = false});

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;
    switch (tone) {
      case Tone.neutral:
        background = AppColors.navyLight;
        foreground = AppColors.navy;
      case Tone.ok:
        background = AppColors.okBackground;
        foreground = AppColors.okText;
      case Tone.warn:
        background = AppColors.warnBackground;
        foreground = AppColors.warnText;
      case Tone.danger:
        background = AppColors.errorBackground;
        foreground = AppColors.errorText;
    }
    if (isFilled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: foreground, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: foreground)),
    );
  }
}

enum Tone { neutral, ok, warn, danger }

// ------------------------------------------------------------------ Bộ lọc

/// Hàng nút lọc dạng pill (Đã lên lịch / Quá hạn / Đã xong / Đã hủy).
/// Chọn 1 cái, nút đang chọn nền xanh đậm chữ trắng.
class FilterPills<T> extends StatelessWidget {
  final List<({T value, String label})> options;
  final T selected;
  final ValueChanged<T> onChanged;

  const FilterPills({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: options.length,
        separatorBuilder: (BuildContext context, int index) {
          return const SizedBox(width: 8);
        },
        itemBuilder: (BuildContext context, int index) {
          final ({String label, T value}) option = options[index];
          final bool isSelected = option.value == selected;
          return GestureDetector(
            onTap: () {
              onChanged(option.value);
            },
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.navy : AppColors.surface,
                border: Border.all(color: isSelected ? AppColors.navy : AppColors.border),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                option.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : AppColors.label,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------- Chọn một trong các

/// Ô chọn dạng radio: tiêu đề đậm + chú thích nhỏ, viền xanh khi đang chọn.
/// Dùng cho chọn mức độ hỏng và chọn xe trong chuyến.
class ChoiceTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isSelected;
  final bool isDanger;
  final VoidCallback onTap;

  const ChoiceTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
    this.isDanger = false,
  });

  @override
  Widget build(BuildContext context) {
    // Mức "phải dừng xe" nền đỏ, các ô khác nền trắng
    final Color borderColor = isDanger
        ? (isSelected ? AppColors.errorText : AppColors.errorBackground)
        : (isSelected ? AppColors.navy : AppColors.border);
    final Color background = isDanger && isSelected ? AppColors.errorBackground : AppColors.surface;
    final Color titleColor = isDanger && isSelected ? AppColors.errorText : AppColors.text;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: borderColor, width: isSelected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Vòng tròn tick vẽ tay: trông giống radio nhưng tô màu được theo trạng thái
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? borderColor : AppColors.surface,
                border: Border.all(color: isSelected ? borderColor : AppColors.inputBorder, width: 1.5),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: titleColor)),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.textMuted)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------- Tiến độ bảo hồng

/// Thanh 3 bước ngang: Đã gửi → Quản lý đã nhận → Đã xử lý.
/// Bước nào chưa tới thì nền xám, bước đã qua thì nền xanh đậm.
class BreakdownStepBar extends StatelessWidget {
  final int currentStep;
  final List<String> labels;

  const BreakdownStepBar({
    super.key,
    required this.currentStep,
    required this.labels,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            for (int index = 0; index < labels.length; index++) ...[
              if (index > 0) const SizedBox(width: 4),
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: index <= currentStep ? AppColors.navy : AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            for (int index = 0; index < labels.length; index++)
              Expanded(
                child: Text(
                  labels[index],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: index <= currentStep ? AppColors.navy : AppColors.textMuted,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Dòng thời gian dọc trong màn chi tiết: đã xong thì chấm xanh, chưa tới thì chấm xám.
class TimelineRow extends StatelessWidget {
  final String title;
  final bool isDone;

  const TimelineRow({super.key, required this.title, required this.isDone});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDone ? AppColors.navy : AppColors.surface,
            border: Border.all(color: isDone ? AppColors.navy : AppColors.inputBorder, width: 1.5),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: isDone ? AppColors.text : AppColors.textMuted,
              fontWeight: isDone ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------ Danh sách phân trang

/// Màn danh sách phân trang: gộp các trang đã tải vào một danh sách, cuộn gần đáy thì tải trang sau.
///
/// Màn giữ danh sách và biến trang; widget này chỉ lo vẽ và báo khi cuộn tới đáy.
class PagedListView<T> extends StatefulWidget {
  final AsyncValue<PagedResult<T>> firstPage;
  final List<T> items;
  final bool isLoadingMore;
  final bool hasMore;
  // RefreshIndicator đòi hàm trả Future, nên kiểu này chứ không phải VoidCallback
  final Future<void> Function() onRefresh;
  final VoidCallback onLoadMore;
  final List<Widget> header;
  final Widget Function(T item) itemBuilder;
  final String emptyText;
  final Widget? footer;

  const PagedListView({
    super.key,
    required this.firstPage,
    required this.items,
    required this.isLoadingMore,
    required this.hasMore,
    required this.onRefresh,
    required this.onLoadMore,
    required this.itemBuilder,
    required this.emptyText,
    this.header = const <Widget>[],
    this.footer,
  });

  @override
  State<PagedListView<T>> createState() => _PagedListViewState<T>();
}

class _PagedListViewState<T> extends State<PagedListView<T>> {
  final ScrollController scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    scrollController.addListener(onScroll);
  }

  @override
  void dispose() {
    scrollController.removeListener(onScroll);
    scrollController.dispose();
    super.dispose();
  }

  // Cách cuộn tới đáy 400px thì bắt đầu tải trang sau, để kéo xuống không bị giật
  void onScroll() {
    if (!scrollController.hasClients) {
      return;
    }
    final double remaining = scrollController.position.maxScrollExtent - scrollController.position.pixels;
    if (remaining < 400) {
      widget.onLoadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Đang tải trang sau thì danh sách đã có vẫn phải hiện, không thay bằng vòng xoay.
    // Chỉ khi chưa có món nào thì mới để AsyncView lo trạng thái tải / lỗi.
    final AsyncValue<List<T>> listValue = widget.items.isNotEmpty
        ? AsyncData<List<T>>(widget.items)
        : widget.firstPage.whenData((PagedResult<T> page) => page.items);

    return AsyncView<List<T>>(
      value: listValue,
      onRetry: widget.onRefresh,
      isEmpty: (List<T> pageItems) {
        return pageItems.isEmpty;
      },
      emptyText: widget.emptyText,
      builder: (List<T> _) {
        final List<Widget> children = <Widget>[...widget.header];
        for (final T item in widget.items) {
          children.add(widget.itemBuilder(item));
        }
        if (widget.isLoadingMore) {
          children.add(const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CupertinoActivityIndicator()),
          ));
        } else if (widget.footer != null) {
          children.add(widget.footer!);
        }
        return RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: ListView(
            controller: scrollController,
            padding: withTabBarInset(context, const EdgeInsets.only(bottom: 24)),
            children: children,
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------ Ô nhập ngày

/// Ô nhập ngày: bấm ra lịch chọn ngày. Ô này là nút bấm chứ không cho gõ tay,
/// vì server chỉ nhận đúng định dạng ngày "yyyy-MM-dd".
class DateField extends StatelessWidget {
  final String value;
  final String placeholder;
  final VoidCallback onTap;

  const DateField({
    super.key,
    required this.value,
    required this.onTap,
    this.placeholder = 'dd/mm/yyyy',
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.inputBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined, size: 17, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value.isEmpty ? placeholder : value,
                style: TextStyle(
                  fontSize: 15,
                  color: value.isEmpty ? AppColors.textMuted : AppColors.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}