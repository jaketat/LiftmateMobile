import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/call.dart';
import '../i18n.dart';

// Widget dùng chung cho mọi màn: tự vẽ 1 trong 4 trạng thái (đang tải, có dữ liệu, rỗng, lỗi).
// <T> = kiểu dữ liệu của màn, ví dụ List<Role>. Một widget dùng được cho mọi màn.
class AsyncView<T> extends StatelessWidget {
  // AsyncValue (Riverpod) = kết quả của provider, lấy bằng ref.watch(provider).
  // Nó luôn ở 1 trong 3 dạng: đang tải / có dữ liệu / lỗi.
  final AsyncValue<T> value;

  // Hàm vẽ màn khi đã có dữ liệu. Màn nào tự viết hàm này.
  final Widget Function(T data) builder;

  // Hàm chạy khi bấm "Thử lại". Thường là: ref.invalidate(tenProvider)
  // VoidCallback (Flutter) = hàm không nhận gì, không trả gì
  final VoidCallback onRetry;

  // Hàm kiểm tra dữ liệu có rỗng không. Dấu ? = không bắt buộc
  // (màn danh sách cần, màn chi tiết thì không).
  final bool Function(T data)? isEmpty;

  // Câu hiện khi rỗng, ví dụ "Chưa có vai trò nào."
  final String? emptyText;

  const AsyncView({
    super.key,
    required this.value,
    required this.builder,
    required this.onRetry,
    this.isEmpty,
    // Không truyền emptyText thì dùng câu mặc định này
    this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    // .when (Riverpod): chọn vẽ theo dạng hiện tại của value
    return value.when(
      // Dạng 1: đang gọi API → vòng xoay ở giữa màn
      loading: () {
        return const Center(child: CupertinoActivityIndicator(radius: 14));
      },
      // Dạng 2: gọi API lỗi → câu lỗi + nút "Thử lại"
      error: (Object error, StackTrace stackTrace) {
        return ErrorView(message: errorMessage(error), onRetry: onRetry);
      },
      // Dạng 3: có dữ liệu
      data: (T data) {
        // Có truyền isEmpty và dữ liệu rỗng → trạng thái thứ 4: rỗng
        // isEmpty! : dấu ! = "tôi chắc chắn chỗ này không null" (dòng trên đã kiểm tra)
        if (isEmpty != null && isEmpty!(data)) {
          return EmptyView(text: emptyText ?? t('ui.empty'));
        }
        // Có dữ liệu thật → gọi hàm vẽ của màn
        return builder(data);
      },
    );
  }
}

// Trạng thái lỗi: câu lỗi + nút "Thử lại", nằm giữa màn
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      // Cách mép màn 24 điểm ở mọi phía, để chữ dài không dính sát mép
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          // Cột chỉ cao vừa đủ nội dung, để Center căn được ra giữa
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            // Khoảng trống 16 điểm giữa chữ và nút
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: Text(t('common.retry'))),
          ],
        ),
      ),
    );
  }
}

// Trạng thái rỗng: một câu nằm giữa màn
class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(text, textAlign: TextAlign.center));
  }
}

// Lấy câu lỗi để hiện cho người dùng
String errorMessage(Object error) {
  // Lỗi từ API (đã qua hàm call) → câu tiếng Việt server viết sẵn
  if (error is ApiException) {
    return error.message;
  }
  // Lỗi khác (ví dụ code đọc sai JSON) → câu chung, không để người dùng thấy chữ kỹ thuật
  return t('common.error');
}

// Dùng cho NÚT BẤM (lưu, gửi, xóa...), không dùng cho cả màn:
// bấm lỗi thì hiện thanh báo ở đáy màn, màn vẫn giữ nguyên.
// ScaffoldMessenger, SnackBar (Flutter) = thanh thông báo trượt lên từ đáy màn hình
void showErrorSnackBar(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(errorMessage(error))));
}
