import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../application/anniversary/app_clock.dart';
import '../../../application/anniversary/anniversary_list_controller.dart';
import '../../../application/anniversary/anniversary_models.dart';
import '../../../gateway_interfaces/anniversary_gateway.dart';
import '../../../gateway_interfaces/anniversary_share_gateway.dart';
import '../anniversary_design_tokens.dart';
import '../widgets/anniversary_filter_bar.dart';
import '../widgets/anniversary_list_card.dart';
import 'anniversary_detail_page.dart';
import 'create_anniversary_page.dart';

enum _AnniversaryListMenuAction { create, refresh }

class AnniversaryListPage extends StatefulWidget {
  const AnniversaryListPage({
    required this.gateway,
    required this.shareGateway,
    required this.clock,
    super.key,
  });

  final AnniversaryGateway gateway;
  final AnniversaryShareGateway shareGateway;
  final AppClock clock;

  @override
  State<AnniversaryListPage> createState() => _AnniversaryListPageState();
}

class _AnniversaryListPageState extends State<AnniversaryListPage> {
  late final AnniversaryListController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnniversaryListController(widget.gateway);
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openCreatePage() async {
    final created = await Navigator.of(context).push<AnniversaryDetail>(
      MaterialPageRoute<AnniversaryDetail>(
        builder: (_) =>
            CreateAnniversaryPage(gateway: widget.gateway, clock: widget.clock),
      ),
    );
    if (!mounted || created == null) {
      return;
    }
    await _controller.load();
  }

  Future<void> _openDetail(AnniversaryListItem item) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: RouteSettings(
          name: '/anniversary/detail/${item.anniversary.id}',
        ),
        builder: (_) => AnniversaryDetailPage(
          anniversaryId: item.anniversary.id,
          gateway: widget.gateway,
          shareGateway: widget.shareGateway,
          clock: widget.clock,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    await _controller.load();
  }

  void _handleMenuAction(_AnniversaryListMenuAction action) {
    switch (action) {
      case _AnniversaryListMenuAction.create:
        unawaited(_openCreatePage());
      case _AnniversaryListMenuAction.refresh:
        unawaited(_controller.load());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AnniversaryColors.listBackground,
      ),
      child: Scaffold(
        backgroundColor: AnniversaryColors.listBackground,
        floatingActionButton: Semantics(
          button: true,
          label: '新建纪念日',
          child: FloatingActionButton(
            key: const ValueKey('anniversary-add-button'),
            tooltip: '新建纪念日',
            onPressed: _openCreatePage,
            backgroundColor: AnniversaryColors.primaryTeal,
            foregroundColor: Colors.white,
            shape: const CircleBorder(),
            child: const Icon(Icons.add_rounded, size: 30),
          ),
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AnniversaryListTopBar(onSelected: _handleMenuAction),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AnniversarySpacing.pageHorizontal,
                ),
                child: ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) => AnniversaryFilterBar(
                    selected: _controller.selectedFilter,
                    onSelected: _controller.selectFilter,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AnniversarySpacing.pageHorizontal,
                  ),
                  child: ListenableBuilder(
                    listenable: _controller,
                    builder: (context, _) => _buildContent(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return switch (_controller.phase) {
      AnniversaryListPhase.loading => const Center(
        child: CircularProgressIndicator(color: AnniversaryColors.primaryTeal),
      ),
      AnniversaryListPhase.empty => _AnniversaryStatusView(
        icon: Icons.hourglass_empty_rounded,
        title: '这里还没有纪念日',
        message: '点击右下角的加号，记录一个值得期待的日子。',
        actionLabel: '新建纪念日',
        onAction: _openCreatePage,
      ),
      AnniversaryListPhase.error => _AnniversaryStatusView(
        icon: Icons.cloud_off_rounded,
        title: '纪念日加载失败',
        message: _controller.errorMessage ?? '请稍后重试',
        actionLabel: '重新加载',
        onAction: _controller.load,
      ),
      AnniversaryListPhase.ready => ListView.separated(
        key: const ValueKey('anniversary-list'),
        padding: const EdgeInsets.only(bottom: 104),
        itemCount: _controller.items.length,
        separatorBuilder: (_, _) =>
            const SizedBox(height: AnniversarySpacing.listGap),
        itemBuilder: (context, index) {
          final item = _controller.items[index];
          return AnniversaryListCard(
            key: ValueKey(item.anniversary.id),
            item: item,
            onTap: () => _openDetail(item),
          );
        },
      ),
    };
  }
}

class _AnniversaryListTopBar extends StatelessWidget {
  const _AnniversaryListTopBar({required this.onSelected});

  final ValueChanged<_AnniversaryListMenuAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AnniversarySpacing.pageHorizontal,
          4,
          8,
          0,
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                '倒数纪念日',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AnniversaryColors.primaryText,
                  fontSize: 27,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            PopupMenuButton<_AnniversaryListMenuAction>(
              tooltip: '更多操作',
              onSelected: onSelected,
              icon: const Icon(
                Icons.more_vert_rounded,
                color: AnniversaryColors.primaryText,
              ),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _AnniversaryListMenuAction.create,
                  child: Text('新建纪念日'),
                ),
                PopupMenuItem(
                  value: _AnniversaryListMenuAction.refresh,
                  child: Text('刷新列表'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AnniversaryStatusView extends StatelessWidget {
  const _AnniversaryStatusView({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 80),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AnniversaryColors.cardBackground,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 44, color: AnniversaryColors.secondaryText),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AnniversaryColors.primaryText,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AnniversaryColors.secondaryText,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(
                    backgroundColor: AnniversaryColors.primaryTeal,
                  ),
                  child: Text(actionLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
