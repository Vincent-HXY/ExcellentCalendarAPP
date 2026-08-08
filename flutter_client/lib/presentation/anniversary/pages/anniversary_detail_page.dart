import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../application/anniversary/app_clock.dart';
import '../../../application/anniversary/anniversary_detail_controller.dart';
import '../../../application/anniversary/anniversary_models.dart';
import '../../../gateway_interfaces/anniversary_gateway.dart';
import '../../../gateway_interfaces/anniversary_share_gateway.dart';
import '../anniversary_design_tokens.dart';
import '../widgets/countdown_paper_card.dart';
import 'create_anniversary_page.dart';

enum _DetailMenuAction { edit, delete }

class AnniversaryDetailPage extends StatefulWidget {
  const AnniversaryDetailPage({
    required this.anniversaryId,
    required this.gateway,
    required this.shareGateway,
    required this.clock,
    super.key,
  });

  final String anniversaryId;
  final AnniversaryGateway gateway;
  final AnniversaryShareGateway shareGateway;
  final AppClock clock;

  @override
  State<AnniversaryDetailPage> createState() => _AnniversaryDetailPageState();
}

class _AnniversaryDetailPageState extends State<AnniversaryDetailPage> {
  static const _themeColors = [
    AnniversaryColors.themeMint,
    AnniversaryColors.themeLavender,
    AnniversaryColors.themePeach,
  ];

  late final AnniversaryDetailController _controller;
  int _themeIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnniversaryDetailController(
      anniversaryId: widget.anniversaryId,
      gateway: widget.gateway,
      shareGateway: widget.shareGateway,
    );
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleMenu(_DetailMenuAction action) async {
    switch (action) {
      case _DetailMenuAction.edit:
        await _edit();
      case _DetailMenuAction.delete:
        await _delete();
    }
  }

  Future<void> _edit() async {
    final current = _controller.detail;
    if (current == null) {
      return;
    }
    final updated = await Navigator.of(context).push<AnniversaryDetail>(
      MaterialPageRoute<AnniversaryDetail>(
        builder: (_) => CreateAnniversaryPage(
          gateway: widget.gateway,
          clock: widget.clock,
          initialDetail: current,
        ),
      ),
    );
    if (!mounted || updated == null) {
      return;
    }
    _controller.replaceDetail(updated);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除纪念日？'),
        content: const Text('删除后它将不再出现在倒数纪念日列表中。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AnniversaryColors.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final deleted = await _controller.delete();
    if (!mounted) {
      return;
    }
    if (deleted) {
      Navigator.of(context).pop();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_controller.errorMessage ?? '删除失败，请稍后重试')),
    );
  }

  Future<void> _showNote() async {
    final note = _controller.detail?.anniversary.note;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '备注',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              Text(
                note == null || note.trim().isEmpty ? '暂时没有备注' : note,
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseTheme() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '选择卡片主题',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.spaceAround,
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (var index = 0; index < _themeColors.length; index++)
                    Semantics(
                      selected: index == _themeIndex,
                      button: true,
                      label: '主题 ${index + 1}',
                      child: InkWell(
                        onTap: () => Navigator.of(sheetContext).pop(index),
                        borderRadius: BorderRadius.circular(28),
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: _themeColors[index],
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: index == _themeIndex
                                  ? AnniversaryColors.primaryText
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: index == _themeIndex
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      _themeIndex = selected;
    });
  }

  Future<void> _share() async {
    final error = await _controller.share();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error ?? '分享接口已预留')));
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AnniversaryColors.detailBackground,
      ),
      child: Scaffold(
        backgroundColor: AnniversaryColors.detailBackground,
        body: SafeArea(
          child: Column(
            children: [
              ListenableBuilder(
                listenable: _controller,
                builder: (context, _) => _DetailTopBar(
                  isBusy: _controller.phase == AnniversaryDetailPhase.deleting,
                  onBack: () => Navigator.of(context).maybePop(),
                  onSelected: _handleMenu,
                ),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) => _buildContent(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_controller.phase == AnniversaryDetailPhase.loading) {
      return const Center(
        child: CircularProgressIndicator(color: AnniversaryColors.primaryTeal),
      );
    }
    if (_controller.phase == AnniversaryDetailPhase.error) {
      return _DetailErrorView(
        message: _controller.errorMessage ?? '纪念日加载失败',
        onRetry: _controller.load,
      );
    }

    final detail = _controller.detail;
    if (detail == null) {
      return const SizedBox.shrink();
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 32),
      child: Column(
        children: [
          Center(
            child: CountdownPaperCard(
              detail: detail,
              themeColor: _themeColors[_themeIndex],
            ),
          ),
          const SizedBox(height: 30),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 28,
            runSpacing: 18,
            children: [
              _DetailActionButton(
                icon: Icons.notes_rounded,
                label: '备注',
                onPressed: _showNote,
              ),
              _DetailActionButton(
                icon: Icons.palette_outlined,
                label: '主题',
                onPressed: _chooseTheme,
              ),
              _DetailActionButton(
                icon: Icons.ios_share_rounded,
                label: '分享',
                onPressed: _share,
              ),
            ],
          ),
          if (_controller.phase == AnniversaryDetailPhase.deleting) ...[
            const SizedBox(height: 24),
            const CircularProgressIndicator(
              color: AnniversaryColors.primaryTeal,
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailTopBar extends StatelessWidget {
  const _DetailTopBar({
    required this.isBusy,
    required this.onBack,
    required this.onSelected,
  });

  final bool isBusy;
  final VoidCallback onBack;
  final ValueChanged<_DetailMenuAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const Expanded(
            child: Text(
              '纪念日详情',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AnniversaryColors.primaryText,
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          PopupMenuButton<_DetailMenuAction>(
            tooltip: '更多操作',
            enabled: !isBusy,
            onSelected: onSelected,
            itemBuilder: (_) => const [
              PopupMenuItem(value: _DetailMenuAction.edit, child: Text('编辑')),
              PopupMenuItem(value: _DetailMenuAction.delete, child: Text('删除')),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailActionButton extends StatelessWidget {
  const _DetailActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: label,
          child: Material(
            color: Colors.white.withValues(alpha: 0.86),
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onPressed,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 58,
                height: 58,
                child: Icon(
                  icon,
                  color: AnniversaryColors.primaryTeal,
                  size: 25,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: AnniversaryColors.primaryText,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _DetailErrorView extends StatelessWidget {
  const _DetailErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.event_busy_rounded,
              size: 44,
              color: AnniversaryColors.secondaryText,
            ),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: AnniversaryColors.primaryTeal,
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
