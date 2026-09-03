import 'package:flutter/material.dart';

import '../../../application/calendar/calendar_date_math.dart';
import '../../../application/calendar/calendar_models.dart';
import '../../../native_contract/calendar/calendar_contract_enums.dart';
import '../../../native_contract/calendar/calendar_response_dtos.dart';
import '../calendar_design_tokens.dart';

class CalendarSections extends StatelessWidget {
  const CalendarSections({
    required this.state,
    required this.onOpenEvent,
    required this.onOpenHabit,
    required this.onOpenAnniversary,
    required this.onLoadMore,
    required this.onRetryFull,
    required this.onCreate,
    super.key,
  });

  final CalendarState state;
  final ValueChanged<CalendarEventItemDto> onOpenEvent;
  final ValueChanged<CalendarHabitItemDto> onOpenHabit;
  final ValueChanged<CalendarAnniversaryItemDto> onOpenAnniversary;
  final ValueChanged<CalendarSection> onLoadMore;
  final VoidCallback onRetryFull;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    if (state.rangePhase == CalendarRangePhase.error &&
        state.rangeDays.isEmpty) {
      return _FullError(
        message: state.errorMessage ?? '日历加载失败，请稍后重试',
        onRetry: onRetryFull,
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
    final animationKey = ValueKey(
      '${CalendarDateMath.formatDate(state.selectedDate)}:'
      '${state.snapshotToken ?? 'stale'}:'
      '${eventItems.length}:${habitItems.length}:${anniversaryItems.length}',
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
              onRetry: onRetryFull,
            ),
          if (eventItems.isNotEmpty) ...[
            _SectionGroup<CalendarEventItemDto>(
              section: CalendarSection.event,
              title: '日程',
              icon: Icons.schedule_rounded,
              color: CalendarPalette.of(context).event,
              items: eventItems,
              state: state.eventSection,
              itemBuilder: (item) =>
                  _EventCard(item: item, onTap: () => onOpenEvent(item)),
              onLoadMore: () => onLoadMore(CalendarSection.event),
            ),
            const SizedBox(height: CalendarSpacing.sectionGap),
          ],
          if (habitItems.isNotEmpty) ...[
            _SectionGroup<CalendarHabitItemDto>(
              section: CalendarSection.habit,
              title: '习惯',
              icon: Icons.track_changes_rounded,
              color: CalendarPalette.of(context).habit,
              items: habitItems,
              state: state.habitSection,
              itemBuilder: (item) =>
                  _HabitCard(item: item, onTap: () => onOpenHabit(item)),
              onLoadMore: () => onLoadMore(CalendarSection.habit),
            ),
            const SizedBox(height: CalendarSpacing.sectionGap),
          ],
          if (anniversaryItems.isNotEmpty) ...[
            _SectionGroup<CalendarAnniversaryItemDto>(
              section: CalendarSection.anniversary,
              title: '纪念日',
              icon: Icons.celebration_rounded,
              color: CalendarPalette.of(context).anniversary,
              items: anniversaryItems,
              state: state.anniversarySection,
              itemBuilder: (item) => _AnniversaryCard(
                item: item,
                onTap: () => onOpenAnniversary(item),
              ),
              onLoadMore: () => onLoadMore(CalendarSection.anniversary),
            ),
          ],
          if (eventItems.isEmpty &&
              habitItems.isEmpty &&
              anniversaryItems.isEmpty)
            _EmptyState(onCreate: onCreate),
        ],
      ),
    );
  }
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
    required this.section,
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
    required this.state,
    required this.itemBuilder,
    required this.onLoadMore,
  });

  final CalendarSection section;
  final String title;
  final IconData icon;
  final Color color;
  final List<T> items;
  final CalendarSectionState state;
  final Widget Function(T item) itemBuilder;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '$title分组，共${items.length}项',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '${items.length}',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (var index = 0; index < items.length; index++) ...[
          itemBuilder(items[index]),
          if (index != items.length - 1)
            const SizedBox(height: CalendarSpacing.cardGap),
        ],
        if (state.hasMore || state.phase == CalendarSectionPhase.loadingMore)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: state.phase == CalendarSectionPhase.loadingMore
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    )
                  : TextButton.icon(
                      key: ValueKey('calendar-load-more-${section.wireValue}'),
                      onPressed: onLoadMore,
                      icon: const Icon(Icons.expand_more_rounded),
                      label: const Text('加载更多'),
                    ),
            ),
          ),
        if (state.phase == CalendarSectionPhase.error &&
            state.errorMessage != null &&
            state.hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    state.errorMessage!,
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
    ),
  );
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.item, required this.onTap});

  final CalendarEventItemDto item;
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
      color: palette.event,
      background: palette.eventContainer,
      semanticsLabel:
          '日程，${item.title}，$time，$status'
          '${item.hasActiveReminder ? '，有提醒' : ''}',
      onTap: onTap,
      child: Opacity(
        opacity: skipped ? 0.70 : 1,
        child: _ItemContent(
          icon: Icons.schedule_rounded,
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
  const _HabitCard({required this.item, required this.onTap});

  final CalendarHabitItemDto item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = CalendarPalette.of(context);
    final status = _habitStatusLabel(item.status);
    final progress = _habitProgress(item);
    return _CalendarItemShell(
      key: ValueKey(item.identityKey),
      color: palette.habit,
      background: palette.habitContainer,
      semanticsLabel:
          '习惯，${item.title}，$status'
          '${progress == null ? '' : '，$progress'}'
          '${item.hasActiveReminder ? '，有提醒' : ''}',
      onTap: onTap,
      child: _ItemContent(
        icon: item.status == CalendarHabitItemStatus.done
            ? Icons.check_circle_rounded
            : Icons.track_changes_rounded,
        title: item.title,
        subtitle: progress == null ? status : '$status · $progress',
        badge: status,
        hasReminder: item.hasActiveReminder,
      ),
    );
  }
}

class _AnniversaryCard extends StatelessWidget {
  const _AnniversaryCard({required this.item, required this.onTap});

  final CalendarAnniversaryItemDto item;
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
      color: palette.anniversary,
      background: palette.anniversaryContainer,
      semanticsLabel:
          '纪念日，${item.title}，$relation'
          '${item.hasActiveReminder ? '，有提醒' : ''}',
      onTap: onTap,
      child: _ItemContent(
        icon: Icons.celebration_rounded,
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
    required this.color,
    required this.background,
    required this.semanticsLabel,
    required this.onTap,
    required this.child,
    super.key,
  });

  final Color color;
  final Color background;
  final String semanticsLabel;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticsLabel,
    excludeSemantics: true,
    child: Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CalendarRadius.card),
        side: BorderSide(color: color.withValues(alpha: 0.24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned.fill(
              left: 0,
              right: null,
              child: ColoredBox(color: color, child: const SizedBox(width: 4)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 13, 14, 13),
              child: child,
            ),
          ],
        ),
      ),
    ),
  );
}

class _ItemContent extends StatelessWidget {
  const _ItemContent({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.hasReminder,
    this.badge,
    this.titleDecoration,
  });

  final IconData icon;
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
        child: Icon(
          icon,
          size: 21,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 18),
    child: Column(
      children: [
        SizedBox(
          width: 76,
          height: 64,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 50,
                color: Theme.of(context).colorScheme.primary,
              ),
              Positioned(
                right: 2,
                bottom: 1,
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 22,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 15),
        Text('这一天还没有安排', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 7),
        Text(
          '添加一项日程、习惯或纪念日，让计划从这里开始。',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey('calendar-empty-create'),
          onPressed: onCreate,
          icon: const Icon(Icons.add_rounded),
          label: const Text('新建安排'),
        ),
      ],
    ),
  );
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
