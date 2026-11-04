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
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../auth/session_provider.dart';
import '../roles/role_detail_screen.dart';
import '../../core/widgets/ios.dart';
import '../../core/widgets/page_transition.dart';

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
    showIosToast(context, t('fleet.openUriFailed'), isError: true);
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

  Pill(this.text, {super.key, required this.background, required this.foreground});
  Pill.ok(this.text, {super.key}) : background = AppColors.okBackground, foreground = AppColors.okText;
  Pill.warn(this.text, {super.key}) : background = AppColors.warnBackground, foreground = AppColors.warnText;
  Pill.error(this.text, {super.key}) : background = AppColors.errorBackground, foreground = AppColors.errorText;
  Pill.navy(this.text, {super.key}) : background = AppColors.navyLight, foreground = AppColors.navy;
  Pill.gray(this.text, {super.key}) : background = AppColors.fillSoft, foreground = AppColors.label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: foreground)),
    );
  }
}

// Nhãn hạn giấy tờ: hết hạn / còn ≤ 3 ngày đỏ, ≤ 7 ngày vàng, còn lâu xanh
Pill daysPill(int days) {
  if (days < 0) {
    return Pill.error(t('home.expiredDays', <String, Object?>{'days': -days}));
  }
  if (days == 0) {
    return Pill.error(t('documents.expiresToday'));
  }
  if (days <= 3) {
    return Pill.error(t('documents.daysLeft', <String, Object?>{'days': days}));
  }
  if (days <= 7) {
    return Pill.warn(t('documents.daysLeft', <String, Object?>{'days': days}));
  }
  return Pill.ok(t('fleet.valid'));
}

// Một dòng "nhãn ..... giá trị"
class InfoRow extends StatelessWidget {
  final String labelText;
  final String value;

  InfoRow(this.labelText, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(labelText, style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
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

  StatTile(this.value, this.labelText, {super.key, Color? color}) : color = color ?? AppColors.text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
        Text(labelText, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
      ],
    );
  }
}

// Ô tìm kiếm: gõ xong 0,4 giây mới báo ra ngoài, đỡ gọi API mỗi phím
class SearchField extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onChanged;

  SearchField({super.key, required this.hint, required this.onChanged});

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

  FilterChips({super.key, required this.options, required this.selected, required this.onSelected});

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
      padding: EdgeInsets.symmetric(horizontal: 16),
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

  PagedList({super.key, required this.fetchPage, required this.itemBuilder, required this.emptyText});

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
          padding: withTabBarInset(context, const EdgeInsets.fromLTRB(16, 8, 16, 96)),
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
                child: TextButton(onPressed: loadMore, child: Text(t('fleet.loadMoreFailed'))),
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
  String? saveText,
}) {
  return showIosDialog<String>(
    context,
    builder: (BuildContext dialogContext) {
      return _AskTextDialog(
        title: title,
        fieldLabel: fieldLabel,
        initialText: initialText,
        isNumber: isNumber,
        saveText: saveText ?? t('common.save'),
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

  _AskTextDialog({
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
        errorText = t('fleet.enterField', <String, Object?>{'field': widget.fieldLabel.toLowerCase()});
      });
      return;
    }
    if (widget.isNumber && num.tryParse(text) == null) {
      setState(() {
        errorText = t('fleet.numberInvalid');
      });
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return IosDialog(
      title: widget.title,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: <Widget>[
          CupertinoTextField(
            controller: controller,
            autofocus: true,
            placeholder: widget.fieldLabel,
            keyboardType: widget.isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
            onSubmitted: (String _) => submit(),
          ),
          if (errorText != null) Text(errorText!, style: TextStyle(fontSize: 13, color: AppColors.errorText)),
        ],
      ),
      actions: <IosDialogAction>[
        IosDialogAction(label: t('fleet.cancel'), style: IosDialogActionStyle.secondary, onPressed: () => Navigator.of(context).pop()),
        IosDialogAction(label: widget.saveText, style: IosDialogActionStyle.primary, onPressed: submit),
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

  DocTile({super.key, required this.doc, required this.typeName, required this.detail, this.onVoid});

  @override
  Widget build(BuildContext context) {
    Widget pill = daysPill(daysUntil(doc.effectiveUntil));
    String detailText = detail;
    if (doc.isVoided) {
      pill = Pill.gray(t('fleet.voided'));
      detailText = doc.voidReason ?? t('fleet.voided');
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
                Text(detailText, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
              ],
            ),
          ),
          if (onVoid != null && !doc.isVoided) TextButton(onPressed: onVoid, child: Text(t('fleet.void'))),
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
        color: isMuted ? AppColors.fillSoft : AppColors.navyLight,
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

  TapCard({super.key, required this.child, this.onTap, Color? borderColor, this.borderWidth = 1}) : borderColor = borderColor ?? AppColors.border;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: AppColors.surface,
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
