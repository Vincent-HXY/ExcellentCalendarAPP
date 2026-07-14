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
      height: 90,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: eventDetailCardDecoration(),
      child: Row(
        children: [
          Expanded(
            child: _MetaColumn(
              label: '\u5b8c\u6210\u72b6\u6001',
              graphic: _CompletionIndicator(percent: state.completionPercent),
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
    );
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
