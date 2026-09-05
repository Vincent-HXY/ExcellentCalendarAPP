import 'package:flutter/material.dart';

import '../../../application/calendar/calendar_date_math.dart';
import '../../../application/calendar/calendar_models.dart';
import '../../../native_contract/calendar/calendar_contract_enums.dart';
import '../../../native_contract/calendar/calendar_response_dtos.dart';
import '../../app_design_tokens.dart';
import '../calendar_design_tokens.dart';

class CalendarSections extends StatefulWidget {
  const CalendarSections({
    required this.state,
    required this.onOpenEvent,
    required this.onOpenHabit,
    required this.onOpenAnniversary,
    required this.onLoadMore,
    required this.onRetryFull,
    super.key,
  });

  final CalendarState state;
  final ValueChanged<CalendarEventItemDto> onOpenEvent;
  final ValueChanged<CalendarHabitItemDto> onOpenHabit;
  final ValueChanged<CalendarAnniversaryItemDto> onOpenAnniversary;
  final ValueChanged<CalendarSection> onLoadMore;
  final VoidCallback onRetryFull;

  @override
  State<CalendarSections> createState() => _CalendarSectionsState();
}

class _CalendarSectionsState extends State<CalendarSections> {
  bool _completedExpanded = false;
  bool _eventExpanded = true;
  bool _habitExpanded = true;
  bool _anniversaryExpanded = true;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    if (state.rangePhase == CalendarRangePhase.error &&
        state.rangeDays.isEmpty) {
      return _FullError(
        message: state.errorMessage ?? '日历加载失败，请稍后重试',
        onRetry: widget.onRetryFull,
      );
    }
    final sections = [
      state.eventSection,
      state.habitSection,
      state.anniversarySection,
    ];
    final selectedLoading = sections.every(
      (section) =>
          section.items.isEmpty &&
          (section.phase == CalendarSectionPhase.loading ||
              section.phase == CalendarSectionPhase.initial),
    );
    if (selectedLoading) return const _SectionSkeleton();

    final eventItems = state.eventSection.items
        .whereType<CalendarEventItemDto>()
        .toList(growable: false);
    final habitItems = state.habitSection.items
        .whereType<CalendarHabitItemDto>()
        .toList(growable: false);
    final anniversaryItems = state.anniversarySection.items
        .whereType<CalendarAnniversaryItemDto>()
        .toList(growable: false);
    final completedItems = <CalendarDayItemDto>[
      ...eventItems.where(
        (item) => item.status == CalendarEventItemStatus.completed,
      ),
      ...habitItems.where(
        (item) => item.status == CalendarHabitItemStatus.done,
      ),
    ];
    final openEventItems = eventItems
        .where((item) => item.status != CalendarEventItemStatus.completed)
        .toList(growable: false);
    final openHabitItems = habitItems
        .where((item) => item.status != CalendarHabitItemStatus.done)
        .toList(growable: false);
    final groupCards = <Widget>[
      if (completedItems.isNotEmpty)
        _SectionGroup<CalendarDayItemDto>(
          key: const ValueKey('calendar-section-card-completed'),
          groupId: 'completed',
          title: '已完成',
          items: completedItems,
          isExpanded: _completedExpanded,
          emptyMessage: '今天还没有已完成事项',
          onToggle: () =>
              setState(() => _completedExpanded = !_completedExpanded),
          itemBuilder: (item, showDivider) => switch (item) {
            CalendarEventItemDto event => _EventCard(
              item: event,
              showDivider: showDivider,
              onTap: () => widget.onOpenEvent(event),
            ),
            CalendarHabitItemDto habit => _HabitCard(
              item: habit,
              showDivider: showDivider,
              onTap: () => widget.onOpenHabit(habit),
            ),
            _ => const SizedBox.shrink(),
          },
        ),
      if (_shouldShowSection(state.eventSection, openEventItems))
        _SectionGroup<CalendarEventItemDto>(
          key: const ValueKey('calendar-section-card-event'),
          groupId: CalendarSection.event.wireValue,
          section: CalendarSection.event,
          title: '日程',
          items: openEventItems,
          state: state.eventSection,
          isExpanded: _eventExpanded,
          emptyMessage: '今天暂无日程',
          onToggle: () => setState(() => _eventExpanded = !_eventExpanded),
          itemBuilder: (item, showDivider) => _EventCard(
            item: item,
            showDivider: showDivider,
            onTap: () => widget.onOpenEvent(item),
          ),
          onLoadMore: () => widget.onLoadMore(CalendarSection.event),
        ),
      if (_shouldShowSection(state.habitSection, openHabitItems))
        _SectionGroup<CalendarHabitItemDto>(
          key: const ValueKey('calendar-section-card-habit'),
          groupId: CalendarSection.habit.wireValue,
          section: CalendarSection.habit,
          title: '习惯',
          items: openHabitItems,
          state: state.habitSection,
          isExpanded: _habitExpanded,
          emptyMessage: '今天暂无习惯',
          onToggle: () => setState(() => _habitExpanded = !_habitExpanded),
          itemBuilder: (item, showDivider) => _HabitCard(
            item: item,
            showDivider: showDivider,
            onTap: () => widget.onOpenHabit(item),
          ),
          onLoadMore: () => widget.onLoadMore(CalendarSection.habit),
        ),
      if (_shouldShowSection(state.anniversarySection, anniversaryItems))
        _SectionGroup<CalendarAnniversaryItemDto>(
          key: const ValueKey('calendar-section-card-anniversary'),
          groupId: CalendarSection.anniversary.wireValue,
          section: CalendarSection.anniversary,
          title: '纪念日',
          items: anniversaryItems,
          state: state.anniversarySection,
          isExpanded: _anniversaryExpanded,
          emptyMessage: '今天暂无纪念日',
          onToggle: () =>
              setState(() => _anniversaryExpanded = !_anniversaryExpanded),
          itemBuilder: (item, showDivider) => _AnniversaryCard(
            item: item,
            showDivider: showDivider,
            onTap: () => widget.onOpenAnniversary(item),
          ),
          onLoadMore: () => widget.onLoadMore(CalendarSection.anniversary),
        ),
    ];
    final animationKey = ValueKey(
      <String>[
        CalendarDateMath.formatDate(state.selectedDate),
        for (final item in eventItems) item.identityKey,
        for (final item in habitItems) item.identityKey,
        for (final item in anniversaryItems) item.identityKey,
      ].join(':'),
    );
    return AnimatedSwitcher(
      duration: CalendarMotion.effective(context, CalendarMotion.section),
      switchInCurve: Curves.easeOut,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.035),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: Column(
        key: animationKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SelectedDateHeading(date: state.selectedDate),
          if (state.rangePhase == CalendarRangePhase.error)
            _InlineError(
              message: state.errorMessage ?? '刷新失败，当前仍显示上次内容',
              onRetry: widget.onRetryFull,
            ),
          if (groupCards.isEmpty)
            const _CalendarEmptyState()
          else
            for (var index = 0; index < groupCards.length; index++) ...[
              if (index > 0) const SizedBox(height: CalendarSpacing.sectionGap),
              groupCards[index],
            ],
        ],
      ),
    );
  }

  bool _shouldShowSection<T extends CalendarDayItemDto>(
    CalendarSectionState state,
    List<T> items,
  ) =>
      items.isNotEmpty ||
      state.hasMore ||
      state.phase == CalendarSectionPhase.loadingMore ||
      state.phase == CalendarSectionPhase.error;
}

class _SelectedDateHeading extends StatelessWidget {
  const _SelectedDateHeading({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final weekday = const [
      '周一',
      '周二',
      '周三',
      '周四',
      '周五',
      '周六',
      '周日',
    ][date.weekday - 1];
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 14),
      child: Semantics(
        header: true,
        child: Text(
          '${date.month}月${date.day}日 · $weekday',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}

class _SectionGroup<T extends CalendarDayItemDto> extends StatelessWidget {
  const _SectionGroup({
    required this.groupId,
    required this.title,
    required this.items,
    required this.isExpanded,
    required this.emptyMessage,
    required this.onToggle,
    required this.itemBuilder,
    this.section,
    this.state,
    this.onLoadMore,
    super.key,
  });

  final String groupId;
  final CalendarSection? section;
  final String title;
  final List<T> items;
  final CalendarSectionState? state;
  final bool isExpanded;
  final String emptyMessage;
  final VoidCallback onToggle;
  final Widget Function(T item, bool showDivider) itemBuilder;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final expandDuration = disableAnimations
        ? Duration.zero
        : AppMotion.sectionExpand;
    final collapseDuration = disableAnimations
        ? Duration.zero
        : AppMotion.sectionCollapse;
    final arrowDuration = disableAnimations
        ? Duration.zero
        : AppMotion.arrowRotation;
    final palette = CalendarPalette.of(context);
    return Semantics(
      container: true,
      label: '$title分组，共${items.length}项，${isExpanded ? '已展开' : '已折叠'}',
      child: Container(
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(AppRadius.sectionCard),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              button: true,
              label: '${isExpanded ? '折叠' : '展开'}$title',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: ValueKey('calendar-section-toggle-$groupId'),
                  onTap: onToggle,
                  child: SizedBox(
                    height: 48,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(
                            '${items.length}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: palette.mutedText),
                          ),
                          const SizedBox(width: 10),
                          AnimatedRotation(
                            turns: isExpanded ? 0.25 : 0,
                            duration: arrowDuration,
                            curve: AppMotion.standard,
                            child: Icon(
                              Icons.chevron_right_rounded,
                              color: palette.mutedText,
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: expandDuration,
              reverseDuration: collapseDuration,
              curve: AppMotion.standard,
              alignment: Alignment.topCenter,
              child: ClipRect(
                child: isExpanded
                    ? Padding(
                        key: ValueKey('calendar-section-body-$groupId'),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildBody(context),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final currentState = state;
    if (items.isEmpty &&
        currentState != null &&
        (currentState.phase == CalendarSectionPhase.initial ||
            currentState.phase == CalendarSectionPhase.loading)) {
      return const SizedBox(
        height: 44,
        child: Center(
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (items.isEmpty &&
        currentState?.phase == CalendarSectionPhase.error &&
        currentState?.errorMessage != null) {
      return _SectionMessage(message: currentState!.errorMessage!);
    }
    final hasMore = currentState?.hasMore == true;
    final loadingMore = currentState?.phase == CalendarSectionPhase.loadingMore;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (items.isEmpty) _SectionMessage(message: emptyMessage),
        for (var index = 0; index < items.length; index++) ...[
          itemBuilder(items[index], index != items.length - 1),
        ],
        if (hasMore || loadingMore)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Center(
              child: loadingMore
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    )
                  : TextButton.icon(
                      key: ValueKey('calendar-load-more-${section!.wireValue}'),
                      onPressed: onLoadMore,
                      icon: const Icon(Icons.expand_more_rounded),
                      label: const Text('加载更多'),
                    ),
            ),
          ),
        if (currentState?.phase == CalendarSectionPhase.error &&
            currentState?.errorMessage != null &&
            hasMore)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 6, 10, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    currentState!.errorMessage!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                TextButton(onPressed: onLoadMore, child: const Text('重试')),
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionMessage extends StatelessWidget {
  const _SectionMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: Center(
      child: Text(
        message,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: CalendarPalette.of(context).mutedText,
        ),
      ),
    ),
  );
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.item,
    required this.showDivider,
    required this.onTap,
  });

  final CalendarEventItemDto item;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = CalendarPalette.of(context);
    final completed = item.status == CalendarEventItemStatus.completed;
    final skipped = item.status == CalendarEventItemStatus.skipped;
    final status = _eventStatusLabel(item.status);
    final time = switch (item.dayDisplay) {
      CalendarEventDayDisplay.allDay => '全天',
      CalendarEventDayDisplay.startsAt => item.displayLocalTime!,
      CalendarEventDayDisplay.continues => '进行中',
      CalendarEventDayDisplay.endsAt => '${item.displayLocalTime!} 结束',
    };
    return _CalendarItemShell(
      key: ValueKey(item.identityKey),
      showDivider: showDivider,
      semanticsLabel:
          '日程，${item.title}，$time，$status'
          '${item.hasActiveReminder ? '，有提醒' : ''}',
      onTap: onTap,
      child: Opacity(
        opacity: skipped ? 0.70 : 1,
        child: _ItemContent(
          icon: Icons.schedule_rounded,
          iconColor: palette.event,
          title: item.title,
          titleDecoration: completed ? TextDecoration.lineThrough : null,
          subtitle: '$time · $status',
          badge: item.isRecurring ? '重复' : null,
          hasReminder: item.hasActiveReminder,
        ),
      ),
    );
  }
}

class _HabitCard extends StatelessWidget {
  const _HabitCard({
    required this.item,
    required this.showDivider,
    required this.onTap,
  });

  final CalendarHabitItemDto item;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = CalendarPalette.of(context);
    final status = _habitStatusLabel(item.status);
    final progress = _habitProgress(item);
    return _CalendarItemShell(
      key: ValueKey(item.identityKey),
      showDivider: showDivider,
      semanticsLabel:
          '习惯，${item.title}，$status'
          '${progress == null ? '' : '，$progress'}'
          '${item.hasActiveReminder ? '，有提醒' : ''}',
      onTap: onTap,
      child: _ItemContent(
        icon: item.status == CalendarHabitItemStatus.done
            ? Icons.check_circle_rounded
            : Icons.track_changes_rounded,
        iconColor: palette.habit,
        title: item.title,
        subtitle: progress == null ? status : '$status · $progress',
        badge: status,
        hasReminder: item.hasActiveReminder,
      ),
    );
  }
}

class _AnniversaryCard extends StatelessWidget {
  const _AnniversaryCard({
    required this.item,
    required this.showDivider,
    required this.onTap,
  });

  final CalendarAnniversaryItemDto item;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = CalendarPalette.of(context);
    final relation = item.isRepeating
        ? item.yearsElapsed == 0
              ? '纪念日起点'
              : '第 ${item.yearsElapsed} 周年'
        : '一次性纪念日';
    return _CalendarItemShell(
      key: ValueKey(item.identityKey),
      showDivider: showDivider,
      semanticsLabel:
          '纪念日，${item.title}，$relation'
          '${item.hasActiveReminder ? '，有提醒' : ''}',
      onTap: onTap,
      child: _ItemContent(
        icon: Icons.celebration_rounded,
        iconColor: palette.anniversary,
        title: item.title,
        subtitle: relation,
        badge: item.importance == CalendarAnniversaryImportance.importantUrgent
            ? '重要紧急'
            : null,
        hasReminder: item.hasActiveReminder,
      ),
    );
  }
}

class _CalendarItemShell extends StatelessWidget {
  const _CalendarItemShell({
    required this.showDivider,
    required this.semanticsLabel,
    required this.onTap,
    required this.child,
    super.key,
  });

  final bool showDivider;
  final String semanticsLabel;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticsLabel,
    excludeSemantics: true,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: showDivider
                ? Border(
                    bottom: BorderSide(
                      color: CalendarPalette.of(
                        context,
                      ).outline.withValues(alpha: 0.55),
                      width: 0.75,
                    ),
                  )
                : null,
          ),
          padding: const EdgeInsets.fromLTRB(22, 12, 18, 12),
          child: child,
        ),
      ),
    ),
  );
}

class _ItemContent extends StatelessWidget {
  const _ItemContent({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.hasReminder,
    this.badge,
    this.titleDecoration,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String? badge;
  final bool hasReminder;
  final TextDecoration? titleDecoration;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Icon(icon, size: 21, color: iconColor),
      ),
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                decoration: titleDecoration,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 8),
      Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(CalendarRadius.chip),
              ),
              child: Text(
                badge!,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          if (hasReminder) ...[
            const SizedBox(height: 6),
            const Tooltip(
              message: '已设置提醒',
              child: Icon(Icons.notifications_active_outlined, size: 18),
            ),
          ],
        ],
      ),
    ],
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(
          Icons.sync_problem_rounded,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('重试')),
      ],
    ),
  );
}

class _FullError extends StatelessWidget {
  const _FullError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 42),
    child: Column(
      children: [
        Icon(
          Icons.cloud_off_rounded,
          size: 46,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 14),
        Text('日历暂时无法加载', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 7),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey('calendar-full-retry'),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('重新加载'),
        ),
      ],
    ),
  );
}

class _CalendarEmptyState extends StatelessWidget {
  const _CalendarEmptyState();

  @override
  Widget build(BuildContext context) {
    final palette = CalendarPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: const ValueKey('calendar-empty-state'),
      padding: const EdgeInsets.fromLTRB(12, 30, 12, 52),
      child: Column(
        children: [
          Semantics(
            image: true,
            label: '没有待办任务的日历插画',
            child: ExcludeSemantics(
              child: SizedBox(
                width: 168,
                height: 118,
                child: CustomPaint(
                  painter: _EmptyTaskPainter(
                    accent: scheme.primary,
                    secondary: palette.habit,
                    paper: palette.card,
                    outline: palette.mutedText,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '空空如也的任务',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTaskPainter extends CustomPainter {
  const _EmptyTaskPainter({
    required this.accent,
    required this.secondary,
    required this.paper,
    required this.outline,
  });

  final Color accent;
  final Color secondary;
  final Color paper;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawOval(
      Rect.fromCenter(center: center, width: 150, height: 94),
      Paint()..color = accent.withValues(alpha: 0.08),
    );

    final sheet = RRect.fromRectAndRadius(
      Rect.fromLTWH(38, 15, 92, 88),
      const Radius.circular(14),
    );
    canvas.drawRRect(
      sheet.shift(const Offset(0, 5)),
      Paint()..color = outline.withValues(alpha: 0.10),
    );
    canvas.drawRRect(sheet, Paint()..color = paper);
    canvas.drawRRect(
      sheet,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = outline.withValues(alpha: 0.22),
    );

    final linePaint = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = outline.withValues(alpha: 0.30);
    final checkPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = secondary;
    for (var index = 0; index < 3; index++) {
      final y = 40.0 + index * 20;
      canvas.drawCircle(
        Offset(57, y),
        6,
        Paint()..color = secondary.withValues(alpha: 0.13),
      );
      final check = Path()
        ..moveTo(53.5, y)
        ..lineTo(56.5, y + 3)
        ..lineTo(61.5, y - 3);
      canvas.drawPath(check, checkPaint);
      canvas.drawLine(Offset(72, y), Offset(111, y), linePaint);
    }

    canvas.drawCircle(
      const Offset(128, 24),
      11,
      Paint()..color = accent.withValues(alpha: 0.16),
    );
    final sparkle = Path()
      ..moveTo(128, 16)
      ..lineTo(130.5, 21.5)
      ..lineTo(136, 24)
      ..lineTo(130.5, 26.5)
      ..lineTo(128, 32)
      ..lineTo(125.5, 26.5)
      ..lineTo(120, 24)
      ..lineTo(125.5, 21.5)
      ..close();
    canvas.drawPath(sparkle, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(covariant _EmptyTaskPainter oldDelegate) =>
      oldDelegate.accent != accent ||
      oldDelegate.secondary != secondary ||
      oldDelegate.paper != paper ||
      oldDelegate.outline != outline;
}

class _SectionSkeleton extends StatelessWidget {
  const _SectionSkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Padding(
      key: const ValueKey('calendar-section-skeleton'),
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FractionallySizedBox(
            widthFactor: 0.38,
            alignment: Alignment.centerLeft,
            child: Container(
              height: 24,
              decoration: _skeletonDecoration(color),
            ),
          ),
          const SizedBox(height: 16),
          for (var index = 0; index < 3; index++) ...[
            Container(height: 78, decoration: _skeletonDecoration(color)),
            if (index != 2) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  BoxDecoration _skeletonDecoration(Color color) => BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(CalendarRadius.card),
  );
}

String _eventStatusLabel(CalendarEventItemStatus status) => switch (status) {
  CalendarEventItemStatus.pending => '待开始',
  CalendarEventItemStatus.inProgress => '进行中',
  CalendarEventItemStatus.overdue => '已逾期',
  CalendarEventItemStatus.completed => '已完成',
  CalendarEventItemStatus.skipped => '已跳过',
};

String _habitStatusLabel(CalendarHabitItemStatus status) => switch (status) {
  CalendarHabitItemStatus.upcoming => '未到日期',
  CalendarHabitItemStatus.absent => '待完成',
  CalendarHabitItemStatus.partial => '进行中',
  CalendarHabitItemStatus.done => '已完成',
  CalendarHabitItemStatus.skipped => '已跳过',
  CalendarHabitItemStatus.missed => '未完成',
};

String? _habitProgress(CalendarHabitItemDto item) {
  final target = item.targetCountHundredths;
  final unit = item.unit;
  if (target == null || unit == null) return null;
  final completed = item.completedCountHundredths ?? 0;
  return '${formatCalendarHundredths(completed)} / '
      '${formatCalendarHundredths(target)} $unit';
}

String formatCalendarHundredths(int value) {
  final whole = value ~/ 100;
  final fraction = value.abs() % 100;
  if (fraction == 0) return '$whole';
  final encoded = fraction
      .toString()
      .padLeft(2, '0')
      .replaceFirst(RegExp(r'0$'), '');
  return '$whole.$encoded';
}
