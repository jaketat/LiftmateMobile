// Mảnh giao diện + model dùng chung cho các màn người 4 (đội xe, nhân sự, trang chủ, khách hàng).
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// Riverpod: WidgetRef
import 'package:flutter_riverpod/flutter_riverpod.dart';
// url_launcher: mở app gọi điện, email
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/paged_result.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../auth/session_provider.dart';
import '../roles/role_detail_screen.dart';

// Người đang đăng nhập có quyền này không. Chưa có phiên thì coi như không.
bool userCan(WidgetRef ref, String permission) {
  final Session? session = ref.watch(sessionProvider).value;
  return session != null && session.can(permission);
}

// Ngày từ server (có thể kèm giờ, vd "2027-03-12T00:00:00Z") → "12/03/2027" theo giờ điện thoại
String formatDay(String? isoText) {
  if (isoText == null) {
    return '';
  }
  return dateFormat.format(DateTime.parse(isoText).toLocal());
}

// Còn bao nhiêu ngày tới hạn. Âm là đã quá hạn.
int daysUntil(String isoText) {
  final DateTime end = DateTime.parse(isoText).toLocal();
  final DateTime now = DateTime.now();
  return DateTime(end.year, end.month, end.day).difference(DateTime(now.year, now.month, now.day)).inDays;
}

// Gọi điện / gửi email bằng app của máy
Future<void> openUri(BuildContext context, Uri uri) async {
  final bool opened = await launchUrl(uri);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Máy không mở được ứng dụng phù hợp.')));
  }
}

void callPhone(BuildContext context, String phone) {
  openUri(context, Uri(scheme: 'tel', path: phone));
}

// Lỗi của một ô từ errors[] của server. Tên ô server có thể viết hoa chữ đầu nên so không phân biệt hoa thường.
String? fieldError(Map<String, String> errors, String field) {
  for (final MapEntry<String, String> entry in errors.entries) {
    if (entry.key.toLowerCase() == field.toLowerCase()) {
      return entry.value;
    }
  }
  return null;
}

// Nhãn tròn nhỏ có màu
class Pill extends StatelessWidget {
  final String text;
  final Color background;
  final Color foreground;

  const Pill(this.text, {super.key, required this.background, required this.foreground});
  const Pill.ok(this.text, {super.key}) : background = AppColors.okBackground, foreground = AppColors.okText;
  const Pill.warn(this.text, {super.key}) : background = AppColors.warnBackground, foreground = AppColors.warnText;
  const Pill.error(this.text, {super.key}) : background = AppColors.errorBackground, foreground = AppColors.errorText;
  const Pill.navy(this.text, {super.key}) : background = AppColors.navyLight, foreground = AppColors.navy;
  const Pill.gray(this.text, {super.key}) : background = const Color(0xFFF2F4F7), foreground = AppColors.label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: foreground)),
    );
  }
}

// Nhãn hạn giấy tờ: hết hạn / còn ≤ 3 ngày đỏ, ≤ 7 ngày vàng, còn lâu xanh
Pill daysPill(int days) {
  if (days < 0) {
    return Pill.error('Hết hạn ${-days} ngày');
  }
  if (days == 0) {
    return const Pill.error('Hết hạn hôm nay');
  }
  if (days <= 3) {
    return Pill.error('Còn $days ngày');
  }
  if (days <= 7) {
    return Pill.warn('Còn $days ngày');
  }
  return const Pill.ok('Còn hạn');
}

// Một dòng "nhãn ..... giá trị"
class InfoRow extends StatelessWidget {
  final String labelText;
  final String value;

  const InfoRow(this.labelText, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(labelText, style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// Tiêu đề nhóm + nút chữ bên phải (vd "Giấy tờ ..... Thêm, gia hạn")
Widget sectionHeader(String text, {String? actionText, VoidCallback? onAction}) {
  return Row(
    children: [
      Expanded(child: DetailSectionTitle(text)),
      if (actionText != null && onAction != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: TextButton(onPressed: onAction, child: Text(actionText)),
        ),
    ],
  );
}

// Một con số lớn + chữ nhỏ bên dưới (dùng ở trang chủ, chi tiết khách)
class StatTile extends StatelessWidget {
  final String value;
  final String labelText;
  final Color color;

  const StatTile(this.value, this.labelText, {super.key, this.color = AppColors.text});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
        Text(labelText, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
      ],
    );
  }
}

// Ô tìm kiếm: gõ xong 0,4 giây mới báo ra ngoài, đỡ gọi API mỗi phím
class SearchField extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onChanged;

  const SearchField({super.key, required this.hint, required this.onChanged});

  @override
  State<SearchField> createState() {
    return _SearchFieldState();
  }
}

class _SearchFieldState extends State<SearchField> {
  Timer? timer;

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      decoration: InputDecoration(hintText: widget.hint, prefixIcon: const Icon(Icons.search)),
      textInputAction: TextInputAction.search,
      onChanged: (String text) {
        timer?.cancel();
        timer = Timer(const Duration(milliseconds: 400), () {
          widget.onChanged(text.trim());
        });
      },
    );
  }
}

// Hàng nút lọc cuộn ngang. Khóa null = "Tất cả".
class FilterChips extends StatelessWidget {
  final Map<String?, String> options;
  final String? selected;
  final ValueChanged<String?> onSelected;

  const FilterChips({super.key, required this.options, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final List<Widget> chips = <Widget>[];
    for (final MapEntry<String?, String> option in options.entries) {
      final bool isOn = option.key == selected;
      chips.add(Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(option.value),
          selected: isOn,
          showCheckmark: false,
          selectedColor: AppColors.navy,
          labelStyle: TextStyle(color: isOn ? Colors.white : AppColors.label, fontWeight: FontWeight.w500),
          onSelected: (bool _) {
            onSelected(option.key);
          },
        ),
      ));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: chips),
    );
  }
}

// Danh sách có phân trang: cuộn gần cuối thì tải trang tiếp (doc mục 2.5).
// Đổi bộ lọc thì bên ngoài đổi key để danh sách tải lại từ trang 1.
class PagedList<T> extends StatefulWidget {
  final Future<PagedResult<T>> Function(int pageNumber) fetchPage;
  final Widget Function(T item) itemBuilder;
  final String emptyText;

  const PagedList({super.key, required this.fetchPage, required this.itemBuilder, required this.emptyText});

  @override
  State<PagedList<T>> createState() {
    return _PagedListState<T>();
  }
}

class _PagedListState<T> extends State<PagedList<T>> {
  final List<T> items = <T>[];
  int nextPage = 1;
  bool hasNextPage = true;
  bool isLoading = false;
  Object? error;

  @override
  void initState() {
    super.initState();
    loadMore();
  }

  Future<void> loadMore() async {
    if (isLoading || !hasNextPage) {
      return;
    }
    setState(() {
      isLoading = true;
      error = null;
    });
    try {
      final PagedResult<T> page = await widget.fetchPage(nextPage);
      if (!mounted) {
        return;
      }
      setState(() {
        items.addAll(page.items);
        hasNextPage = page.hasNextPage;
        nextPage = nextPage + 1;
        isLoading = false;
      });
    } catch (caught) {
      if (!mounted) {
        return;
      }
      setState(() {
        error = caught;
        isLoading = false;
      });
    }
  }

  Future<void> reload() async {
    if (isLoading) {
      return;
    }
    items.clear();
    nextPage = 1;
    hasNextPage = true;
    await loadMore();
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      if (error != null) {
        return ErrorView(message: errorMessage(error!), onRetry: loadMore);
      }
      if (isLoading || hasNextPage) {
        return const Center(child: CupertinoActivityIndicator(radius: 14));
      }
      return EmptyView(text: widget.emptyText);
    }

    return RefreshIndicator(
      onRefresh: reload,
      // NotificationListener (Flutter): nghe sự kiện cuộn, gần cuối (còn < 300px) thì tải tiếp
      child: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification notification) {
          if (notification.metrics.extentAfter < 300) {
            loadMore();
          }
          return false;
        },
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          itemCount: items.length + 1,
          itemBuilder: (BuildContext context, int index) {
            if (index < items.length) {
              return widget.itemBuilder(items[index]);
            }
            // Dòng cuối: đang tải tiếp / lỗi tải tiếp
            if (isLoading) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CupertinoActivityIndicator(radius: 14)),
              );
            }
            if (error != null) {
              return Center(
                child: TextButton(onPressed: loadMore, child: const Text('Tải tiếp bị lỗi. Thử lại')),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

// Hộp hỏi một dòng chữ (số km, giờ máy, lý do hủy). Trả về chữ đã nhập, null nếu bấm Hủy.
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String fieldLabel,
  String initialText = '',
  bool isNumber = false,
  String saveText = 'Lưu',
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) {
      return _AskTextDialog(
        title: title,
        fieldLabel: fieldLabel,
        initialText: initialText,
        isNumber: isNumber,
        saveText: saveText,
      );
    },
  );
}

class _AskTextDialog extends StatefulWidget {
  final String title;
  final String fieldLabel;
  final String initialText;
  final bool isNumber;
  final String saveText;

  const _AskTextDialog({
    required this.title,
    required this.fieldLabel,
    required this.initialText,
    required this.isNumber,
    required this.saveText,
  });

  @override
  State<_AskTextDialog> createState() {
    return _AskTextDialogState();
  }
}

class _AskTextDialogState extends State<_AskTextDialog> {
  late final TextEditingController controller = TextEditingController(text: widget.initialText);
  String? errorText;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    final String text = controller.text.trim();
    if (text.isEmpty) {
      setState(() {
        errorText = 'Chưa nhập ${widget.fieldLabel.toLowerCase()}.';
      });
      return;
    }
    if (widget.isNumber && num.tryParse(text) == null) {
      setState(() {
        errorText = 'Nhập số, vd 128450 hoặc 3420.5';
      });
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: widget.isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        decoration: InputDecoration(labelText: widget.fieldLabel, errorText: errorText),
        onSubmitted: (String _) {
          submit();
        },
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Hủy'),
        ),
        FilledButton(onPressed: submit, child: Text(widget.saveText)),
      ],
    );
  }
}

// Giấy tờ (của xe hoặc của người): cùng một kiểu dữ liệu (doc mục 3.3, 3.4)
class ComplianceDoc {
  final String publicId;
  final String documentType;
  final String? documentNumber;
  final String? issuedBy;
  final String? issuedAt;
  final String effectiveUntil;
  // Khác null: giấy này hết hạn thì xe không được chạy. Null: chỉ nhắc.
  final String? blocksCapability;
  final bool isVoided;
  final String? voidReason;

  ComplianceDoc({
    required this.publicId,
    required this.documentType,
    required this.documentNumber,
    required this.issuedBy,
    required this.issuedAt,
    required this.effectiveUntil,
    required this.blocksCapability,
    required this.isVoided,
    required this.voidReason,
  });

  factory ComplianceDoc.fromJson(Map<String, dynamic> data) {
    return ComplianceDoc(
      publicId: data['publicId'] as String,
      documentType: data['documentType'] as String,
      documentNumber: data['documentNumber'] as String?,
      issuedBy: data['issuedBy'] as String?,
      issuedAt: data['issuedAt'] as String?,
      effectiveUntil: data['effectiveUntil'] as String,
      blocksCapability: data['blocksCapability'] as String?,
      isVoided: (data['isVoided'] as bool?) ?? false,
      voidReason: data['voidReason'] as String?,
    );
  }
}

List<ComplianceDoc> parseDocs(dynamic data) {
  final List<ComplianceDoc> docs = <ComplianceDoc>[];
  for (final dynamic row in data as List<dynamic>) {
    docs.add(ComplianceDoc.fromJson(row as Map<String, dynamic>));
  }
  return docs;
}

// Một dòng giấy tờ: tên, nhãn hạn, hạn đến, nút Hủy (nếu được). Bản đã hủy: gạch ngang + lý do.
class DocTile extends StatelessWidget {
  final ComplianceDoc doc;
  final String typeName;
  final String detail;
  final VoidCallback? onVoid;

  const DocTile({super.key, required this.doc, required this.typeName, required this.detail, this.onVoid});

  @override
  Widget build(BuildContext context) {
    Widget pill = daysPill(daysUntil(doc.effectiveUntil));
    String detailText = detail;
    if (doc.isVoided) {
      pill = const Pill.gray('Đã hủy');
      detailText = doc.voidReason ?? 'Đã hủy';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        typeName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: doc.isVoided ? AppColors.textMuted : AppColors.text,
                          decoration: doc.isVoided ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    pill,
                  ],
                ),
                const SizedBox(height: 2),
                Text(detailText, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
              ],
            ),
          ),
          if (onVoid != null && !doc.isVoided) TextButton(onPressed: onVoid, child: const Text('Hủy')),
        ],
      ),
    );
  }
}

// Vòng tròn chữ tắt tên, vd "TX"
class InitialsAvatar extends StatelessWidget {
  final String name;
  final double size;
  final bool isMuted;

  const InitialsAvatar(this.name, {super.key, this.size = 44, this.isMuted = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isMuted ? const Color(0xFFF2F4F7) : AppColors.navyLight,
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: Text(
        initialsOf(name),
        style: TextStyle(
          color: isMuted ? AppColors.label : AppColors.navy,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.32,
        ),
      ),
    );
  }
}

// Thẻ trắng bấm được, dùng cho dòng của các danh sách
class TapCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color borderColor;
  final double borderWidth;

  const TapCard({super.key, required this.child, this.onTap, this.borderColor = AppColors.border, this.borderWidth = 1});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: borderColor, width: borderWidth),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: child),
      ),
    );
  }
}
