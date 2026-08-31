import 'package:flutter/material.dart';

import '../../../application/habit/habit_models.dart';
import '../../../native_contract/habit/habit_contract_enums.dart';
import '../habit_design.dart';

class HabitCard extends StatelessWidget {
  const HabitCard({
    required this.item,
    required this.mutating,
    required this.succeeded,
    required this.onOpen,
    required this.onQuickAction,
    required this.onExactQuantity,
    super.key,
  });
  final HabitCardViewData item;
  final bool mutating;
  final bool succeeded;
  final VoidCallback onOpen;
  final VoidCallback? onQuickAction;
  final VoidCallback? onExactQuantity;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final status = _statusLabel(item.todayStatus);
    final remainingCount = item.remainingCountHundredths;
    return Semantics(
      container: true,
      liveRegion: succeeded,
      label:
          '${item.title}，$status，连续 ${item.currentStreak} 天，'
          '剩余 ${item.remainingDays} 天${succeeded ? '，操作成功' : ''}',
      child: AnimatedScale(
        scale: succeeded ? 1.018 : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        child: Material(
          color: succeeded
              ? Theme.of(context).colorScheme.primaryContainer
              : HabitDesign.surface(context),
          borderRadius: BorderRadius.circular(HabitDesign.radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpen,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      key: ValueKey('habit-completion-background-${item.id}'),
                      widthFactor: item.completionRate,
                      child: ColoredBox(color: color.withValues(alpha: 0.09)),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      if (onQuickAction != null) ...[
                        Semantics(
                          button: true,
                          enabled: !mutating,
                          label: item.isQuantitative
                              ? item.hasMetQuantitativeTarget
                                    ? '${item.title} 今日已达标，增加 1 ${item.unit}'
                                    : '${item.title} 剩余 ${formatHundredths(remainingCount!)} ${item.unit}，增加 1 ${item.unit}'
                              : item.todayStatus ==
                                    HabitDailyStatusContract.done
                              ? '${item.title} 撤销今日完成'
                              : '${item.title} 标记今日完成',
                          child: InkResponse(
                            onTap: mutating ? null : onQuickAction,
                            radius: 28,
                            child: SizedBox.square(
                              dimension: 48,
                              child: mutating
                                  ? Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: color,
                                      ),
                                    )
                                  : item.isQuantitative
                                  ? item.hasMetQuantitativeTarget
                                        ? Icon(
                                            Icons.check_circle_rounded,
                                            key: ValueKey(
                                              'habit-target-met-${item.id}',
                                            ),
                                            size: 34,
                                            color: color,
                                          )
                                        : DecoratedBox(
                                            key: ValueKey(
                                              'habit-remaining-${item.id}',
                                            ),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: color,
                                                width: 2.5,
                                              ),
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.all(7),
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(
                                                  formatHundredths(
                                                    remainingCount!,
                                                  ),
                                                  maxLines: 1,
                                                  style: TextStyle(
                                                    color: color,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          )
                                  : Icon(
                                      item.todayStatus ==
                                              HabitDailyStatusContract.done
                                          ? Icons.check_circle_rounded
                                          : Icons
                                                .radio_button_unchecked_rounded,
                                      size: 34,
                                      color: color,
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: HabitDesign.text(context),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Wrap(
                              spacing: 10,
                              runSpacing: 4,
                              children: [
                                Text(status),
                                Text('连续 ${item.currentStreak} 天'),
                                Text('剩余 ${item.remainingDays} 天'),
                                if (item.reminderEnabled)
                                  Text('提醒 ${item.reminderLocalTime ?? ''}'),
                              ],
                            ),
                            if (item.isQuantitative &&
                                onExactQuantity != null) ...[
                              const SizedBox(height: 8),
                              Semantics(
                                button: true,
                                label:
                                    '精确输入数量，当前 ${formatHundredths(item.completedCountHundredths ?? 0)} ${item.unit}',
                                child: InkWell(
                                  onTap: mutating ? null : onExactQuantity,
                                  onLongPress: mutating
                                      ? null
                                      : onExactQuantity,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minHeight: 48,
                                    ),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        '${formatHundredths(item.completedCountHundredths ?? 0)} / '
                                        '${formatHundredths(item.targetCountHundredths!)} ${item.unit}',
                                        style: TextStyle(
                                          color: color,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Semantics(
                        label:
                            '完成率 ${(item.completionRate * 100).round()}%，'
                            '当前连续 ${item.currentStreak} 天',
                        child: SizedBox.square(
                          dimension: 48,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: item.completionRate,
                                strokeWidth: 5,
                                color: color,
                                backgroundColor: color.withValues(alpha: 0.13),
                              ),
                              Text(
                                '${item.currentStreak}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _statusLabel(HabitDailyStatusContract? value) => switch (value) {
  HabitDailyStatusContract.upcoming => '即将开始',
  HabitDailyStatusContract.absent => '今日待完成',
  HabitDailyStatusContract.partial => '今日进行中',
  HabitDailyStatusContract.done => '今日已完成',
  HabitDailyStatusContract.skipped => '今日已跳过',
  HabitDailyStatusContract.missed => '未完成',
  null => '不在挑战日期内',
};
