import 'package:flutter/material.dart';

import '../event_detail_design_tokens.dart';
import '../models/event_detail_ui_state.dart';

class EventNoteCard extends StatelessWidget {
  const EventNoteCard({required this.state, this.onTap, super.key});

  final EventDetailUiState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      decoration: eventDetailCardDecoration(),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(EventDetailSizes.cardRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(EventDetailSizes.cardRadius),
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: EventDetailSpacing.cardPadding,
              vertical: 7,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.description_outlined,
                  size: 20,
                  color: EventDetailColors.secondaryText,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    state.content ?? state.description ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: EventDetailTextStyles.note,
                  ),
                ),
                const SizedBox(width: 7),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: Color(0xFF9BA4AA),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
