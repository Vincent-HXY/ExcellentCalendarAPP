import 'package:flutter/material.dart';

import '../event_detail_design_tokens.dart';
import '../models/event_detail_ui_state.dart';
import '../painters/calendar_star_icon_painter.dart';

class EventSummaryCard extends StatelessWidget {
  const EventSummaryCard({required this.state, super.key});

  final EventDetailUiState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: EventDetailSizes.summaryHeight,
      padding: const EdgeInsets.all(EventDetailSpacing.cardPadding),
      decoration: eventDetailCardDecoration(),
      child: Row(
        children: [
          const SizedBox(
            width: 34,
            height: 34,
            child: CustomPaint(painter: CalendarStarIconPainter()),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        state.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: EventDetailTextStyles.summaryTitle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusPill(label: state.displayStatusLabel),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  state.description ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: EventDetailTextStyles.summaryDescription,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: EventDetailColors.warningBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: EventDetailColors.warningOrange,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
