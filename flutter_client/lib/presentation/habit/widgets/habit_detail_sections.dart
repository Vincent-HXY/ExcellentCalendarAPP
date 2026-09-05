import 'package:flutter/material.dart';

import '../../../application/habit/habit_models.dart';
import '../../../native_contract/habit/habit_contract_enums.dart';
import '../../../native_contract/habit/habit_response_dtos.dart';
import '../habit_design.dart';
import 'habit_page_components.dart';

class HabitDetailOverview extends StatelessWidget {
  const HabitDetailOverview({required this.detail, super.key});

  final HabitDetailViewData detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statistics = detail.dto.statistics;
    final timeProgress = detail.dto.challengeTimeProgress;
    return HabitSectionCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HabitLabel(text: habitLifecycleLabel(detail.lifecycle)),
          const SizedBox(height: 14),
          Text(
            detail.habit.title,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.4,
            ),
          ),
          if (detail.habit.description != null) ...[
            const SizedBox(height: 8),
            Text(
              detail.habit.description!,
              style: TextStyle(color: HabitDesign.muted(context), height: 1.6),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            '${formatHabitDate(detail.habit.startDate)} — ${formatHabitDate(detail.habit.endDate)}',
            style: TextStyle(
              color: HabitDesign.muted(context),
              fontSize: 12,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Semantics(
                label: '挑战时间进度 ${(timeProgress * 100).round()}%',
                child: SizedBox.square(
                  dimension: 64,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: CircularProgressIndicator(
                          value: timeProgress,
                          strokeWidth: 5,
                          strokeCap: StrokeCap.round,
                          color: scheme.primary,
                          backgroundColor: scheme.primary.withValues(
                            alpha: 0.10,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(9),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${(timeProgress * 100).round()}%',
                            style: TextStyle(
                              color: scheme.primary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '剩余 ${detail.dto.remainingDays} 天',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '挑战时间进度',
                      style: TextStyle(
                        color: HabitDesign.muted(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Divider(),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = MediaQuery.textScalerOf(context).scale(1) > 1.4
                  ? 1
                  : 2;
              final width =
                  (constraints.maxWidth - (columns - 1) * 14) / columns;
              return Wrap(
                spacing: 14,
                runSpacing: 18,
                children: [
                  _Metric(
                    width: width,
                    value: '${statistics.currentStreak} 天',
                    label: '当前连续',
                    icon: Icons.local_fire_department_outlined,
                  ),
                  _Metric(
                    width: width,
                    value: '${statistics.longestStreak} 天',
                    label: '最长连续',
                    icon: Icons.emoji_events_outlined,
                  ),
                  _Metric(
                    width: width,
                    value: '${(statistics.completionRateAll * 100).round()}%',
                    label: '全周期完成率',
                    icon: Icons.donut_large_rounded,
                  ),
                  _Metric(
                    width: width,
                    value: '${statistics.doneDays} 天',
                    label: '累计完成',
                    icon: Icons.check_circle_outline_rounded,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.width,
    required this.value,
    required this.label,
    required this.icon,
  });

  final double width;
  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(icon, size: 15, color: HabitDesign.muted(context)),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: HabitDesign.muted(context),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class HabitHeatmap extends StatelessWidget {
  const HabitHeatmap({required this.history, required this.onTap, super.key});

  final List<HabitDailyStatusResponseDto> history;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => HabitSectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HabitSectionHeading(
          title: '挑战热力图',
          subtitle: '最近记录 · 点选日期，回看当天',
          icon: Icons.grid_view_rounded,
        ),
        if (history.isEmpty)
          Text(
            '每一次记录，都会在这里留下足迹。',
            style: TextStyle(color: HabitDesign.muted(context)),
          ),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final day in history.take(60))
              _HeatmapDay(day: day, onTap: () => onTap(day.date)),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            for (final status in [
              HabitDailyStatusContract.done,
              HabitDailyStatusContract.partial,
              HabitDailyStatusContract.skipped,
              HabitDailyStatusContract.missed,
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    habitDayStatusIcon(status),
                    size: 14,
                    color: HabitDesign.muted(context),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    habitDayStatusLabel(status),
                    style: TextStyle(
                      color: HabitDesign.muted(context),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    ),
  );
}

class _HeatmapDay extends StatelessWidget {
  const _HeatmapDay({required this.day, required this.onTap});

  final HabitDailyStatusResponseDto day;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (day.status) {
      HabitDailyStatusContract.done => (scheme.primary, scheme.onPrimary),
      HabitDailyStatusContract.partial => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      HabitDailyStatusContract.missed => (
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
      _ => (HabitDesign.tint(context), HabitDesign.muted(context)),
    };
    final label =
        '${formatHabitDate(day.date)}，${habitDayStatusLabel(day.status)}';
    final size = MediaQuery.textScalerOf(context).scale(24).clamp(48.0, 72.0);
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox.square(
            dimension: size,
            child: Container(
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${DateTime.parse(day.date).day}',
                      style: TextStyle(
                        fontSize: 12,
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 2,
                    child: Icon(
                      habitDayStatusIcon(day.status),
                      size: 10,
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HabitHistory extends StatelessWidget {
  const HabitHistory({required this.history, required this.onTap, super.key});

  final List<HabitDailyStatusResponseDto> history;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => HabitSectionCard(
    padding: const EdgeInsets.only(top: 18, bottom: 6),
    child: Column(
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18),
          child: HabitSectionHeading(
            title: '历史记录',
            icon: Icons.history_rounded,
          ),
        ),
        if (history.isEmpty)
          const Padding(padding: EdgeInsets.all(20), child: Text('这里还没有历史记录')),
        for (var index = 0; index < history.length; index++) ...[
          if (index > 0) const Divider(indent: 72, endIndent: 18),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 3,
            ),
            leading: HabitIconBadge(
              icon: habitDayStatusIcon(history[index].status),
              size: 38,
            ),
            title: Text(
              formatHabitDate(history[index].date),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              habitDayStatusLabel(history[index].status),
              style: TextStyle(fontSize: 12, color: HabitDesign.muted(context)),
            ),
            trailing: Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: HabitDesign.muted(context),
            ),
            onTap: () => onTap(history[index].date),
          ),
        ],
      ],
    ),
  );
}
