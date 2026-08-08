import 'package:flutter/material.dart';

import '../../../application/anniversary/anniversary_models.dart';
import '../anniversary_design_tokens.dart';

class AnniversaryListCard extends StatelessWidget {
  const AnniversaryListCard({
    required this.item,
    required this.onTap,
    super.key,
  });

  final AnniversaryListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final countdown = item.countdown;
    final isElapsed = countdown.relation == CountdownRelation.elapsed;
    final accent = isElapsed
        ? AnniversaryColors.elapsedGreen
        : AnniversaryColors.primaryTeal;

    return RepaintBoundary(
      child: Semantics(
        button: true,
        label: _semanticLabel(item),
        child: Material(
          color: AnniversaryColors.cardBackground,
          borderRadius: BorderRadius.circular(AnniversarySizes.listCardRadius),
          child: InkWell(
            key: ValueKey('anniversary-card-${item.anniversary.id}'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(
              AnniversarySizes.listCardRadius,
            ),
            child: Container(
              constraints: const BoxConstraints(minHeight: 106),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(
                  AnniversarySizes.listCardRadius,
                ),
                boxShadow: AnniversaryShadows.card,
              ),
              child: Row(
                children: [
                  _AnniversaryIcon(iconKey: item.iconKey),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.anniversary.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AnniversaryColors.primaryText,
                            fontSize: 19,
                            height: 1.12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          [
                            countdown.dateLabel,
                            countdown.weekdayLabel,
                          ].where((value) => value.isNotEmpty).join(' '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AnniversaryColors.secondaryText,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 58,
                      maxWidth: 88,
                    ),
                    child: _CountdownValue(snapshot: countdown, accent: accent),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _semanticLabel(AnniversaryListItem item) {
    final snapshot = item.countdown;
    final relation = switch (snapshot.relation) {
      CountdownRelation.remaining => '还有 ${snapshot.days} 天',
      CountdownRelation.elapsed => '已经 ${snapshot.days} 天',
      CountdownRelation.today => '就是今天',
      CountdownRelation.unavailable => '倒数结果待计算',
    };
    return '${item.anniversary.title}，$relation';
  }
}

class _AnniversaryIcon extends StatelessWidget {
  const _AnniversaryIcon({required this.iconKey});

  final String iconKey;

  @override
  Widget build(BuildContext context) {
    final (icon, background, foreground) = switch (iconKey) {
      'cake' => (
        Icons.cake_rounded,
        AnniversaryColors.iconAqua,
        AnniversaryColors.iconAquaForeground,
      ),
      'celebration' => (
        Icons.celebration_rounded,
        AnniversaryColors.iconOrange,
        AnniversaryColors.iconOrangeForeground,
      ),
      'checklist' => (
        Icons.checklist_rounded,
        AnniversaryColors.iconGreen,
        AnniversaryColors.iconGreenForeground,
      ),
      _ => (
        Icons.hourglass_bottom_rounded,
        AnniversaryColors.iconBlue,
        AnniversaryColors.iconBlueForeground,
      ),
    };

    return Container(
      width: AnniversarySizes.iconCircle,
      height: AnniversarySizes.iconCircle,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(icon, color: foreground, size: 25),
    );
  }
}

class _CountdownValue extends StatelessWidget {
  const _CountdownValue({required this.snapshot, required this.accent});

  final CountdownSnapshot snapshot;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (snapshot.relation == CountdownRelation.today) {
      return Text(
        '今天',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: accent,
          fontSize: 23,
          fontWeight: FontWeight.w800,
        ),
      );
    }
    if (snapshot.relation == CountdownRelation.unavailable) {
      return const Text(
        '待计算',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AnniversaryColors.secondaryText,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 42,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${snapshot.days}',
              style: TextStyle(
                color: accent,
                fontSize: 36,
                height: 1,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          snapshot.relation == CountdownRelation.remaining ? '天后' : '天前',
          style: TextStyle(
            color: accent,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
