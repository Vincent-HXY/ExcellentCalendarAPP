import 'package:flutter/material.dart';

import '../../../application/anniversary/anniversary_models.dart';
import '../anniversary_design_tokens.dart';

class CountdownPaperCard extends StatelessWidget {
  const CountdownPaperCard({
    required this.detail,
    required this.themeColor,
    super.key,
  });

  final AnniversaryDetail detail;
  final Color themeColor;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AnniversarySizes.detailCardMaxWidth,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 14, 14),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                left: 12,
                top: 12,
                right: -10,
                bottom: -10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
              Positioned.fill(
                left: 6,
                top: 6,
                right: -5,
                bottom: -5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AnniversaryColors.cardBackground,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x180B4A53),
                      blurRadius: 28,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _BindingHeader(themeColor: themeColor),
                      const _PerforationLine(),
                      _PaperBody(detail: detail, themeColor: themeColor),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BindingHeader extends StatelessWidget {
  const _BindingHeader({required this.themeColor});

  final Color themeColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 86,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [themeColor.withValues(alpha: 0.86), themeColor],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(30, 20, 30, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: const [_BindingPin(), _BindingPin()],
      ),
    );
  }
}

class _BindingPin extends StatelessWidget {
  const _BindingPin();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0x33000000), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: const Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0x33808080),
            shape: BoxShape.circle,
          ),
          child: SizedBox(width: 7, height: 7),
        ),
      ),
    );
  }
}

class _PerforationLine extends StatelessWidget {
  const _PerforationLine();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 14,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dotCount = (constraints.maxWidth / 11).floor();
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(
              dotCount,
              (_) => const DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFFD6E2E4),
                  shape: BoxShape.circle,
                ),
                child: SizedBox(width: 3, height: 3),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PaperBody extends StatelessWidget {
  const _PaperBody({required this.detail, required this.themeColor});

  final AnniversaryDetail detail;
  final Color themeColor;

  @override
  Widget build(BuildContext context) {
    final snapshot = detail.countdown;
    final lead = switch (snapshot.relation) {
      CountdownRelation.remaining =>
        '距离 ${snapshot.dateLabel} ${snapshot.weekdayLabel} 还有',
      CountdownRelation.elapsed =>
        '距离 ${snapshot.dateLabel} ${snapshot.weekdayLabel} 已经',
      CountdownRelation.today =>
        '${snapshot.dateLabel} ${snapshot.weekdayLabel}',
      CountdownRelation.unavailable => '农历日期由底层历法引擎计算',
    };
    final value = switch (snapshot.relation) {
      CountdownRelation.today => '就是今天',
      CountdownRelation.unavailable => '待计算',
      CountdownRelation.remaining ||
      CountdownRelation.elapsed => '${snapshot.days}',
    };

    return Stack(
      children: [
        const Positioned(
          left: 28,
          right: 28,
          top: 74,
          child: Divider(color: Color(0x0D62BDCB), thickness: 1),
        ),
        const Positioned(
          left: 28,
          right: 28,
          top: 136,
          child: Divider(color: Color(0x0D62BDCB), thickness: 1),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                lead,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AnniversaryColors.secondaryText,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 108,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: TextStyle(
                      color: AnniversaryColors.primaryText,
                      fontSize: snapshot.days == null ? 46 : 94,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                detail.anniversary.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: themeColor,
                  fontSize: 27,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 24),
              const Divider(color: AnniversaryColors.divider),
              const SizedBox(height: 8),
              Icon(
                Icons.auto_awesome_rounded,
                size: 20,
                color: themeColor.withValues(alpha: 0.52),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
