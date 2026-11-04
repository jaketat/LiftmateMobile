// Danh sách phân trang cho IosPage: là một sliver nên cuộn chung với tiêu đề lớn, ô tìm và hàng lọc.
// Cuộn tới cuối thì tải trang tiếp. Đổi bộ lọc (query) thì tải lại từ trang 1, giữ danh sách cũ tới khi có kết quả.
import 'package:flutter/cupertino.dart';

import '../api/paged_result.dart';
import '../i18n.dart';
import 'async_view.dart';
import 'ios.dart';

class IosPagedSliver<T> extends StatefulWidget {
  final Future<PagedResult<T>> Function(int pageNumber) fetchPage;
  final Widget Function(T item) itemBuilder;
  final String emptyText;
  final IconData emptyIcon;
  // Dòng chú thích dưới cùng, hiện khi đã tải hết
  final Widget? footer;
  // Gộp các bộ lọc đang chọn: đổi giá trị là tải lại từ trang 1
  final Object? query;

  const IosPagedSliver({
    super.key,
    required this.fetchPage,
    this.query,
    required this.itemBuilder,
    required this.emptyText,
    this.emptyIcon = CupertinoIcons.doc_text,
    this.footer,
  });

  @override
  State<IosPagedSliver<T>> createState() => IosPagedSliverState<T>();
}

class IosPagedSliverState<T> extends State<IosPagedSliver<T>> {
  final List<T> items = <T>[];
  int nextPage = 1;
  bool hasNextPage = true;
  bool loading = false;
  bool loadedOnce = false;
  Object? error;
  // Tải lại khi lượt cũ chưa xong: kết quả lượt cũ bị bỏ
  int generation = 0;

  @override
  void initState() {
    super.initState();
    load(first: true);
  }

  @override
  void didUpdateWidget(IosPagedSliver<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != oldWidget.query) load(first: true);
  }

  // Kéo xuống tải lại: giữ danh sách cũ trên màn tới khi có kết quả mới, không nháy về vòng xoay
  Future<void> reload() => load(first: true);

  Future<void> load({bool first = false}) async {
    if (!first && (loading || !hasNextPage)) return;
    final int current = ++generation;
    final int pageNumber = first ? 1 : nextPage;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final PagedResult<T> page = await widget.fetchPage(pageNumber);
      if (!mounted || current != generation) return;
      setState(() {
        if (first) items.clear();
        items.addAll(page.items);
        hasNextPage = page.hasNextPage;
        nextPage = pageNumber + 1;
        loading = false;
        loadedOnce = true;
      });
    } catch (caught) {
      if (!mounted || current != generation) return;
      setState(() {
        error = caught;
        loading = false;
        loadedOnce = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!loadedOnce) {
      return const SliverFillRemaining(hasScrollBody: false, child: Center(child: CupertinoActivityIndicator(radius: 14)));
    }
    if (items.isEmpty && error != null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: IosCenterMessage(text: errorMessage(error!), icon: widget.emptyIcon, action: t('common.retry'), onAction: reload),
      );
    }
    if (items.isEmpty && !loading) {
      return SliverFillRemaining(hasScrollBody: false, child: IosCenterMessage(text: widget.emptyText, icon: widget.emptyIcon));
    }
    final bool showFooter = widget.footer != null && !hasNextPage && error == null;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      sliver: SliverList.builder(
        itemCount: items.length + (hasNextPage || error != null || showFooter ? 1 : 0),
        itemBuilder: (BuildContext context, int index) {
          if (index < items.length) return widget.itemBuilder(items[index]);
          if (error != null) return CupertinoButton(onPressed: load, child: Text(t('fleet.loadMoreFailed')));
          if (showFooter) return widget.footer!;
          // Cuộn tới cuối thì tải trang tiếp. Đợi hết khung vì đang trong lúc dựng
          WidgetsBinding.instance.addPostFrameCallback((Duration _) {
            if (mounted) load();
          });
          return const Padding(padding: EdgeInsets.all(16), child: Center(child: CupertinoActivityIndicator()));
        },
      ),
    );
  }
}
