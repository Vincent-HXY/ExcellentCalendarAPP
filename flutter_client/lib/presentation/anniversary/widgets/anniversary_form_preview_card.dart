import 'package:flutter/material.dart';

import '../../../application/anniversary/anniversary_form_controller.dart';
import '../../../application/anniversary/anniversary_models.dart';
import '../anniversary_design_tokens.dart';

class AnniversaryFormPreviewCard extends StatelessWidget {
  const AnniversaryFormPreviewCard({
    required this.title,
    required this.preview,
    required this.phase,
    required this.calendarType,
    super.key,
  });

  final String title;
  final CountdownSnapshot? preview;
  final AnniversaryPreviewPhase phase;
  final AnniversaryCalendarType calendarType;

  @override
  Widget build(BuildContext context) {
    final displayTitle = title.trim().isEmpty ? '纪念日名称' : title.trim();
    final countdownLabel = _countdownLabel();
    return Container(
      key: const ValueKey('anniversary-preview-card'),
      constraints: const BoxConstraints(minHeight: 108),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF73C8D3), AnniversaryColors.primaryTeal],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: AnniversaryShadows.card,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.24),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 7),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Text(
                    countdownLabel,
                    key: ValueKey(countdownLabel),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _countdownLabel() {
    if (phase == AnniversaryPreviewPhase.loading) {
      return '正在计算倒数预览…';
    }
    if (calendarType == AnniversaryCalendarType.lunar ||
        preview?.relation == CountdownRelation.unavailable) {
      return '保存后由底层计算';
    }
    if (phase == AnniversaryPreviewPhase.error) {
      return '预览暂不可用';
    }
    final snapshot = preview;
    if (snapshot == null) {
      return '选择日期后显示倒数预览';
    }
    return switch (snapshot.relation) {
      CountdownRelation.remaining => '距离日期还有 ${snapshot.days} 天',
      CountdownRelation.elapsed => '距离日期已经 ${snapshot.days} 天',
      CountdownRelation.today => '就是今天',
      CountdownRelation.unavailable => '待计算',
    };
  }
}
