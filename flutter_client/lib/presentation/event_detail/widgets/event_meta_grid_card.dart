import 'package:flutter/material.dart';

import '../event_detail_design_tokens.dart';
import '../models/event_detail_ui_state.dart';
import '../painters/participant_icon_painter.dart';

class EventMetaGridCard extends StatelessWidget {
  const EventMetaGridCard({required this.state, super.key});

  final EventDetailUiState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: eventDetailCardDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 70,
            child: Row(
              children: [
                Expanded(
                  child: _MetaColumn(
                    label: '\u5b8c\u6210\u72b6\u6001',
                    graphic: _CompletionIndicator(
                      percent: state.completionPercent,
                    ),
                    value: state.completionLabel,
                  ),
                ),
                const _MetaDivider(),
                Expanded(
                  child: _MetaColumn(
                    label: '\u4f18\u5148\u7ea7',
                    graphic: const Icon(
                      Icons.arrow_upward_rounded,
                      size: 26,
                      color: EventDetailColors.warningOrange,
                    ),
                    value: state.priorityLabel,
                  ),
                ),
                const _MetaDivider(),
                Expanded(
                  child: _MetaColumn(
                    label: '\u53c2\u4e0e\u4eba',
                    graphic: const SizedBox(
                      width: 30,
                      height: 28,
                      child: CustomPaint(painter: ParticipantIconPainter()),
                    ),
                    value: '${state.participantCount ?? 0} \u4eba',
                  ),
                ),
                const _MetaDivider(),
                Expanded(
                  child: _MetaColumn(
                    label: '\u5730\u70b9',
                    graphic: const Icon(
                      Icons.location_on_rounded,
                      size: 26,
                      color: EventDetailColors.primaryTeal,
                    ),
                    value: state.location ?? '\u672a\u8bbe\u7f6e',
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(height: 1, color: EventDetailColors.divider),
          ),
          _CategoryRow(category: state.category),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category});

  final EventCategoryUiModel category;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '分类：${category.displayLabel}',
      child: Container(
        key: const ValueKey('event-category-status'),
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            const Text('分类', style: EventDetailTextStyles.metaLabel),
            const SizedBox(width: 14),
            _categoryGraphic(),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                category.displayLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: EventDetailTextStyles.metaValue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryGraphic() => switch (category.status) {
    EventCategoryDisplayStatus.active => DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _colorFromHex(category.color),
      ),
      child: const SizedBox.square(dimension: 14),
    ),
    EventCategoryDisplayStatus.unavailable => const Icon(
      Icons.warning_amber_rounded,
      size: 18,
      color: EventDetailColors.warningOrange,
    ),
    EventCategoryDisplayStatus.unclassified => const Icon(
      Icons.label_off_outlined,
      size: 18,
      color: EventDetailColors.secondaryText,
    ),
  };

  static Color _colorFromHex(String? value) {
    if (value == null || value.length != 7) {
      return EventDetailColors.primaryTeal;
    }
    final rgb = int.tryParse(value.substring(1), radix: 16);
    return rgb == null
        ? EventDetailColors.primaryTeal
        : Color(0xFF000000 | rgb);
  }
}

class _MetaDivider extends StatelessWidget {
  const _MetaDivider();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 58,
      child: VerticalDivider(
        width: 1,
        thickness: .5,
        color: EventDetailColors.divider,
      ),
    );
  }
}

class _MetaColumn extends StatelessWidget {
  const _MetaColumn({
    required this.label,
    required this.graphic,
    required this.value,
  });

  final String label;
  final Widget graphic;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, maxLines: 1, style: EventDetailTextStyles.metaLabel),
        SizedBox(height: 32, child: Center(child: graphic)),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: EventDetailTextStyles.metaValue,
        ),
      ],
    );
  }
}

class _CompletionIndicator extends StatelessWidget {
  const _CompletionIndicator({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              value: percent / 100,
              strokeWidth: 3,
              backgroundColor: const Color(0xFFDCEFF1),
              color: EventDetailColors.primaryTeal,
            ),
          ),
          Text(
            '$percent%',
            style: const TextStyle(
              color: EventDetailColors.primaryTeal,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
