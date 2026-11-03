// LiftMate Intelligence, tạo đơn từ ảnh (thiết kế D3, D4): chụp hoặc dán tin → xem lại chữ AI chép → sửa danh sách kiện.
// AI chỉ chép chữ, người dùng so với ảnh rồi mới đọc thành kiện; hết ô đỏ mới dùng được.
import 'dart:io';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/call.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/liftmate_intelligence.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ios.dart';
import '../../core/widgets/page_transition.dart';
import 'order_form.dart';
import 'orders_api.dart';

/// Công ty tắt AI (server trả AI_DISABLED): ẩn các lối vào, chỉ còn tạo đơn nhập tay. Mở lại danh sách đơn thì hỏi lại server.
final ValueNotifier<bool> orderAiDisabled = ValueNotifier<bool>(false);

enum _Step { capture, review, results }

class OrderAiScreen extends StatefulWidget {
  /// true: xong thì mở form tạo đơn. false: mở từ form, trả danh sách kiện về form.
  final bool thenOpenForm;

  const OrderAiScreen({super.key, required this.thenOpenForm});

  @override
  State<OrderAiScreen> createState() => _OrderAiScreenState();
}

class _OrderAiScreenState extends State<OrderAiScreen> {
  final TextEditingController text = TextEditingController();
  final FocusNode textFocus = FocusNode();
  _Step step = _Step.capture;
  // Đi tới thì trang mới vào từ bên phải, quay lại thì từ bên trái, như đổi trang của iOS
  bool goingBack = false;
  String? photoPath;
  ImageSource photoSource = ImageSource.camera;
  bool reading = false;
  bool parsing = false;
  // Viền sáng vẽ đè lên nút native làm rớt khung: lúc AI đang làm thì trang dùng nút Flutter
  final ValueNotifier<bool> working = ValueNotifier<bool>(false);
  // Lần gọi AI đang chạy. Huỷ thì bỏ token này: kết quả về muộn của lần cũ không được đè lên màn
  CancelToken? aiCall;
  String? error;
  String? dataNotice;
  String? usage;
  List<CargoDraft> cargos = <CargoDraft>[];
  List<String> warnings = <String>[];

  bool get busy => reading || parsing;

  // Chỗ AI không đọc rõ ghi [?]: đọc kiện khi còn [?] thì "6 tấn [?]" thành 6 tấn mà không ai biết (BR-AI-005)
  int get unclear => '[?]'.allMatches(text.text).length;

  int get redCells => cargos.fold(0, (int sum, CargoDraft cargo) => sum + cargo.validate().length);

  // Chỉ sáng viền màn khi AI đang làm: lúc mới bấm vào ô để gõ thì chưa
  bool get glowing => busy;

  @override
  void dispose() {
    aiCall?.cancel();
    textFocus.dispose();
    text.dispose();
    working.dispose();
    super.dispose();
  }

  void handleError(Object e) {
    if (e is ApiException && e.code == 'AI_DISABLED') orderAiDisabled.value = true;
    setState(() => error = errorMessage(e));
  }

  void setUsage(int? used, int? limit) {
    if (used != null && limit != null) usage = t('orderAi.usage', <String, Object?>{'used': used, 'limit': limit});
  }

  Future<void> pick(ImageSource source) async {
    final XFile? file = await ImagePicker().pickImage(source: source);
    if (file == null || !mounted) return;
    if (await file.length() > maxAiImageBytes) {
      if (mounted) setState(() => error = t('orderAi.imageTooBig'));
      return;
    }
    if (!mounted) return;
    setState(() {
      goingBack = false;
      step = _Step.review;
      photoPath = file.path;
      photoSource = source;
      text.clear();
      reading = true;
      error = null;
    });
    working.value = glowing;
    final CancelToken call = aiCall = CancelToken();
    try {
      final AiImageText result = await readCargoImage(file.path, cancelToken: call);
      if (!mounted || call != aiCall) return;
      setState(() {
        text.text = result.text.length > maxAiTextChars ? result.text.substring(0, maxAiTextChars) : result.text;
        dataNotice = result.dataNotice;
        setUsage(result.usedThisMonth, result.monthlyLimit);
      });
    } on FormatException {
      if (mounted && call == aiCall) setState(() => error = t('orderAi.imageUnreadable'));
    } catch (e) {
      if (mounted && call == aiCall) handleError(e);
    }
    if (!mounted || call != aiCall) return;
    aiCall = null;
    setState(() => reading = false);
    working.value = glowing;
  }

  Future<void> parse() async {
    FocusScope.of(context).unfocus();
    setState(() {
      parsing = true;
      error = null;
    });
    working.value = glowing;
    final CancelToken call = aiCall = CancelToken();
    try {
      final AiCargoResult result = await parseCargoText(text.text, cancelToken: call);
      if (!mounted || call != aiCall) return;
      setState(() {
        cargos = result.cargos;
        warnings = result.warnings;
        dataNotice = result.dataNotice;
        setUsage(result.usedThisMonth, result.monthlyLimit);
        goingBack = false;
        step = _Step.results;
      });
    } catch (e) {
      if (mounted && call == aiCall) handleError(e);
    }
    if (!mounted || call != aiCall) return;
    aiCall = null;
    setState(() => parsing = false);
    working.value = glowing;
  }

  /// Dừng chờ AI. Đang chép ảnh thì về bước chọn ảnh; đang đọc kiện thì ở lại, giữ nguyên chữ đã sửa.
  void cancelAi() {
    final CancelToken? call = aiCall;
    if (call == null) return;
    aiCall = null;
    call.cancel();
    setState(() {
      if (reading) {
        goingBack = true;
        step = _Step.capture;
        photoPath = null;
      }
      reading = false;
      parsing = false;
      error = null;
    });
    working.value = glowing;
    showIosToast(context, t('orderAi.cancelled'));
  }

  void useCargos() {
    if (widget.thenOpenForm) {
      context.pushReplacement('/orders/new', extra: cargos);
    } else {
      context.pop(cargos);
    }
  }

  void back() {
    if (busy) {
      cancelAi();
      return;
    }
    if (step == _Step.capture) {
      context.pop();
      return;
    }
    setState(() {
      error = null;
      goingBack = true;
      step = step == _Step.results ? _Step.review : _Step.capture;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: step == _Step.capture && !busy,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) back();
      },
      child: NativeViewsPause(
        paused: working,
        child: AiScreenGlow(
          active: glowing,
          child: IosPage(
        animateTitle: true,
        // Hai vệt màu nền nhìn như vết bẩn trên trang này
        plain: true,
        title: switch (step) {
          // Màn đầu dùng tên LiftMate Intelligence ở giữa thanh trên
          _Step.capture => '',
          _Step.review => photoPath == null ? t('orderAi.pasteTitle') : t('orderAi.reviewTitle'),
          _Step.results => t('orderAi.resultsTitle'),
        },
        barTitle: step == _Step.capture
            ? FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const AiOrb(size: 26),
                    const SizedBox(width: 8),
                    AiGradient(child: Text(t('orderAi.heading'), style: aiTextStyle(19, fontWeight: FontWeight.w600))),
                  ],
                ),
              )
            : null,
        onBack: back,
        trailing: usage == null ? null : Text(usage!, style: TextStyle(fontSize: 12, color: IosColors.secondaryLabel)),
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              // Hai bước nằm chồng lên nhau, căn theo đỉnh, trong lúc chuyển
              layoutBuilder: (Widget? current, List<Widget> previous) => Stack(
                alignment: Alignment.topCenter,
                fit: StackFit.passthrough,
                children: <Widget>[...previous, ?current],
              ),
              transitionBuilder: (Widget child, Animation<double> animation) {
                final bool incoming = child.key == ValueKey<_Step>(step);
                final double from = (incoming ? 1 : -1) * (goingBack ? -0.08 : 0.08);
                return iosFadeThrough(
                  SlideTransition(
                    position: animation.drive(CurveTween(curve: Curves.easeOutCubic)).drive(Tween<Offset>(begin: Offset(from, 0), end: Offset.zero)),
                    child: child,
                  ),
                  animation,
                );
              },
              child: Padding(
                key: ValueKey<_Step>(step),
                // Màn đầu dùng IosGroup, nhóm tự có lề hai bên
                padding: EdgeInsets.fromLTRB(step == _Step.capture ? 0 : 16, 4, step == _Step.capture ? 0 : 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: switch (step) {
                    _Step.capture => _capture(),
                    _Step.review => _review(),
                    _Step.results => _results(),
                  },
                ),
              ),
            ),
          ),
        ],
          ),
        ),
      ),
    );
  }

  Widget _note(String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(value, style: TextStyle(fontSize: 13, height: 1.4, color: color ?? IosColors.secondaryLabel)),
    );
  }

  Widget _errorBox(String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: IosColors.red.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
        child: Text(value, style: TextStyle(fontSize: 14, height: 1.4, color: IosColors.red)),
      ),
    );
  }

  List<Widget> _capture() {
    Widget inset(Widget child) => Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: child);
    Widget icon(IconData value) => AiGradient(child: Icon(value, size: 24, color: Colors.white));
    return <Widget>[
      inset(_note(t('orderAi.description'))),
      const SizedBox(height: 20),
      inset(
        Row(
          children: <Widget>[
            Expanded(child: AiButton(label: t('common.takePhoto'), icon: CupertinoIcons.camera_fill, halo: false, onPressed: () => pick(ImageSource.camera))),
            const SizedBox(width: 10),
            Expanded(child: AiButton(label: t('orderAi.pickExisting'), icon: CupertinoIcons.photo_fill, halo: false, onPressed: () => pick(ImageSource.gallery))),
          ],
        ),
      ),
      if (error != null) inset(_errorBox(error!)),
      const SizedBox(height: 14),
      IosGroup(
        children: <Widget>[
          IosRow(
            leading: icon(CupertinoIcons.chat_bubble_text),
            title: t('orderAi.pasteInstead'),
            onTap: () => setState(() {
              goingBack = false;
              photoPath = null;
              error = null;
              step = _Step.review;
            }),
          ),
        ],
      ),
      // Chỉ để biết AI đọc được gì, không bấm được nên không có mũi tên
      IosGroup(
        header: t('orderAi.kindsHeader'),
        dividerIndent: 56,
        footer: '${t('orderAi.imagePrivacy')} ${t('orderAi.quotaNote')}',
        children: <Widget>[
          IosRow(leading: icon(CupertinoIcons.doc_text), title: t('orderAi.kindList')),
          IosRow(leading: icon(CupertinoIcons.chat_bubble_text), title: t('orderAi.kindZalo')),
          IosRow(leading: icon(CupertinoIcons.gauge), title: t('orderAi.kindWeigh')),
        ],
      ),
    ];
  }

  List<Widget> _review() {
    final bool canParse = !busy && unclear == 0 && text.text.trim().length >= 5;
    return <Widget>[
      if (photoPath != null) ...<Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(t('orderAi.photoTaken'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text))),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 36),
              onPressed: busy ? null : () => pick(photoSource),
              child: AiGradient(child: Text(t('orderAi.retake'), style: aiTextStyle(15, fontWeight: FontWeight.w600))),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: ColoredBox(
            color: Colors.black,
            child: SizedBox(height: 200, child: Image.file(File(photoPath!), fit: BoxFit.contain, cacheHeight: 800)),
          ),
        ),
        const SizedBox(height: 14),
      ],
      if (photoPath != null) ...<Widget>[
        Text(t('orderAi.reviewLabel'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text)),
        const SizedBox(height: 14),
      ],
      if (reading) ...<Widget>[
        const AiGeneratingLines(),
        const SizedBox(height: 16),
        AiShimmerText(t('orderAi.reading'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ] else
        AiReveal(
          animate: photoPath != null,
          // Còn [?] phải sửa thì tắt quầng màu để người dùng chú ý cảnh báo đỏ; đang đọc thì cả màn đã sáng
          child: AiPromptField(
            controller: text,
            focusNode: textFocus,
            enabled: !parsing,
            glow: unclear == 0 && !parsing,
            maxLength: maxAiTextChars,
            placeholder: t('orderAi.placeholder'),
            onChanged: (String _) => setState(() {}),
            onSend: canParse ? parse : null,
          ),
        ),
      const SizedBox(height: 10),
      if (unclear > 0) _errorBox(t('orderAi.unclear', <String, Object?>{'count': unclear})),
      if (error != null) _errorBox(error!),
      if (photoPath != null && (dataNotice ?? '').isNotEmpty) _note(dataNotice!),
      if (photoPath == null) _note(t('orderAi.textPrivacy')),
      const SizedBox(height: 16),
      // Nút tạo đổi sang trạng thái đang đọc thì hiện dần, không nhảy
      AiReveal(
        key: ValueKey<bool>(busy),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: busy
              ? <Widget>[
                  if (parsing) AiShimmerText(t('orderAi.parsing'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: cancelAi,
                    child: Container(
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(999)),
                      child: Text(t('common.cancel'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: IosColors.red)),
                    ),
                  ),
                ]
              : <Widget>[
                  AiButton(label: t('orderAi.parse'), halo: false, onPressed: canParse ? parse : null),
                  _note(t('orderAi.parseNote')),
                ],
        ),
      ),
    ];
  }

  List<Widget> _results() {
    final int red = redCells;
    return <Widget>[
      if (cargos.isEmpty)
        _errorBox(t('orderAi.noCargo'))
      else if (red > 0)
        _errorBox(t('orderAi.redSummary', <String, Object?>{'count': cargos.length, 'red': red}))
      else
        _note(t('orderAi.allGood', <String, Object?>{'count': cargos.length}), color: AppColors.okText),
      for (final String warning in warnings) _note(warning, color: AppColors.warnText),
      const SizedBox(height: 10),
      for (final (int index, CargoDraft cargo) in cargos.indexed)
        AiReveal(
          key: ValueKey<String>(cargo.key),
          delay: Duration(milliseconds: 90 * index),
          child: _AiCargoCard(
            cargo: cargo,
            onChanged: () => setState(() {}),
            onRemove: () => setState(() => cargos.remove(cargo)),
          ),
        ),
      _note(t('orderAi.rawNote')),
      if ((dataNotice ?? '').isNotEmpty) _note(dataNotice!),
      const SizedBox(height: 16),
      AiButton(
        label: t('orderAi.useCargos', <String, Object?>{'count': cargos.length}),
        halo: false,
        onPressed: cargos.isNotEmpty && red == 0 ? useCargos : null,
      ),
      if (red > 0) _note(t('orderAi.useNote')),
    ];
  }
}

class _AiCargoCard extends StatefulWidget {
  final CargoDraft cargo;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _AiCargoCard({required this.cargo, required this.onChanged, required this.onRemove});

  @override
  State<_AiCargoCard> createState() => _AiCargoCardState();
}

class _AiCargoCardState extends State<_AiCargoCard> {
  CargoDraft get cargo => widget.cargo;
  late final TextEditingController name = TextEditingController(text: cargo.cargoName);
  late final TextEditingController quantity = TextEditingController(text: cargo.quantity);
  late final TextEditingController weight = TextEditingController(text: cargo.weightKg);
  late final TextEditingController length = TextEditingController(text: cargo.lengthMm);
  late final TextEditingController width = TextEditingController(text: cargo.widthMm);
  late final TextEditingController height = TextEditingController(text: cargo.heightMm);
  late final TextEditingController saddle = TextEditingController(text: cargo.saddleHeightMm);

  @override
  void dispose() {
    name.dispose();
    quantity.dispose();
    weight.dispose();
    length.dispose();
    width.dispose();
    height.dispose();
    saddle.dispose();
    super.dispose();
  }

  // Gõ vào ô là coi như đã kiểm tra: hết đỏ nếu số hợp lệ
  void edited(String field, void Function() apply) {
    apply();
    cargo.aiFlags.remove(field);
    widget.onChanged();
    setState(() {});
  }

  Widget field(String id, String label, TextEditingController controller, void Function(String) apply, {bool decimal = false, bool isText = false}) {
    final Map<String, String> errors = cargo.validate();
    final AiFlag? flag = cargo.aiFlags[id];
    final bool red = errors.containsKey(id);
    final String? raw = cargo.aiRaws[id];
    final bool canConfirm = flag != null && controller.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: TextStyle(fontSize: 12, color: IosColors.secondaryLabel)),
        const SizedBox(height: 3),
        CupertinoTextField(
          controller: controller,
          keyboardType: isText ? TextInputType.text : (decimal ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.number),
          style: TextStyle(fontSize: 15, color: AppColors.text),
          // Viền đỏ dày hơn 1 px: bớt đệm cho ô không nhảy cỡ
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: red ? 9 : 10),
          decoration: aiFieldDecoration(
            radius: 12,
            border: Border.all(color: red ? IosColors.red : IosColors.separator, width: red ? 2 : 1),
          ),
          onChanged: (String value) => edited(id, () => apply(value)),
        ),
        if ((raw ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text('“$raw”', style: TextStyle(fontSize: 12, color: IosColors.secondaryLabel)),
          ),
        if (red)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(flag?.reason ?? errors[id]!, style: TextStyle(fontSize: 12, color: IosColors.red, height: 1.25)),
          ),
        if (canConfirm)
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 30),
            onPressed: () {
              cargo.aiFlags.remove(id);
              widget.onChanged();
              setState(() {});
            },
            child: AiGradient(child: Text(t('orderAi.correct'), style: aiTextStyle(13, fontWeight: FontWeight.w600))),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final int red = cargo.validate().length;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: red > 0 ? Border.all(color: IosColors.red.withValues(alpha: 0.4)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  red > 0 ? t('orderAi.cellsToConfirm', <String, Object?>{'count': red}) : t('orderAi.complete'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: red > 0 ? IosColors.red : AppColors.okText),
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 30),
                onPressed: widget.onRemove,
                child: Text(t('orderAi.removeCargo'), style: TextStyle(fontSize: 13, color: IosColors.red)),
              ),
            ],
          ),
          field('cargoName', t('orderForm.cargoName'), name, (String v) => cargo.cargoName = v, isText: true),
          for (final String issue in cargo.issues)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(issue, style: TextStyle(fontSize: 12, color: AppColors.warnText, height: 1.3)),
            ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: field('quantity', t('orderForm.quantity'), quantity, (String v) => cargo.quantity = v)),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: field('weightKg', t('orderForm.weight'), weight, (String v) => cargo.weightKg = v, decimal: true)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: field('lengthMm', t('orderForm.length'), length, (String v) => cargo.lengthMm = v)),
              const SizedBox(width: 8),
              Expanded(child: field('widthMm', t('orderForm.width'), width, (String v) => cargo.widthMm = v)),
              const SizedBox(width: 8),
              Expanded(child: field('heightMm', t('orderForm.height'), height, (String v) => cargo.heightMm = v)),
            ],
          ),
          if (cargo.supportType == 'Cylinder') ...<Widget>[
            const SizedBox(height: 10),
            field('saddleHeightMm', t('orderForm.saddleHeight'), saddle, (String v) => cargo.saddleHeightMm = v),
          ],
        ],
      ),
    );
  }
}
