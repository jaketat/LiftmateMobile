class PagedResult<T> {
  final List<T> items;
  final int pageIndex;
  final int totalCount;
  final bool hasNextPage;

  PagedResult(this.items, this.pageIndex, this.totalCount, this.hasNextPage);

  //factory dùng để tạo một constructor có thân hàm: được tính toán trước, rồi mới return ra object
  factory PagedResult.fromJson(
      Map<String, dynamic> data,
      T Function(Map<String, dynamic> rowJson) convertRow,
      ) {
    // 1. Đổi từng dòng JSON trong "items" thành model
    final List<dynamic> rowsJson = data['items'] as List<dynamic>;
    final List<T> items = [];
    for (final dynamic row in rowsJson) {
      final Map<String, dynamic> rowJson = row as Map<String, dynamic>;
      final T model = convertRow(rowJson);
      items.add(model);
    }

    // 2. Lấy các con số của trang
    final int pageIndex = data['pageIndex'] as int;
    final int totalCount = data['totalCount'] as int;
    final bool hasNextPage = data['hasNextPage'] as bool;

    // 3. Tạo object
    return PagedResult(items, pageIndex, totalCount, hasNextPage);
  }
}
