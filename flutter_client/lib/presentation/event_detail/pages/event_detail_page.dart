import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../event_detail_design_tokens.dart';
import '../models/event_detail_ui_state.dart';
import '../widgets/event_detail_action_bar.dart';
import '../widgets/event_meta_grid_card.dart';
import '../widgets/event_note_card.dart';
import '../widgets/event_schedule_card.dart';
import '../widgets/event_summary_card.dart';

class EventDetailPageArguments {
  const EventDetailPageArguments({
    required this.state,
    this.onMore,
    this.onEdit,
    this.onComplete,
    this.onEditField,
  });

  final EventDetailUiState state;
  final VoidCallback? onMore;
  final VoidCallback? onEdit;
  final FutureOr<void> Function()? onComplete;
  final ValueChanged<EventDetailField>? onEditField;
}

class EventDetailPage extends StatefulWidget {
  const EventDetailPage({
    required this.state,
    this.onMore,
    this.onEdit,
    this.onComplete,
    this.onEditField,
    super.key,
  });

  factory EventDetailPage.preview({String eventId = 'preview-event'}) {
    return EventDetailPage(state: EventDetailUiState.preview(eventId: eventId));
  }

  final EventDetailUiState state;
  final VoidCallback? onMore;
  final VoidCallback? onEdit;
  final FutureOr<void> Function()? onComplete;
  final ValueChanged<EventDetailField>? onEditField;

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  var _isCompleting = false;

  Future<void> _handleComplete() async {
    final complete = widget.onComplete;
    if (complete == null || _isCompleting) return;
    setState(() => _isCompleting = true);
    try {
      await complete();
    } finally {
      if (mounted) setState(() => _isCompleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: Scaffold(
        extendBody: true,
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    EventDetailColors.backgroundStart,
                    EventDetailColors.backgroundMiddle,
                    EventDetailColors.backgroundEnd,
                  ],
                ),
              ),
            ),
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(.72, -.1),
                    radius: 1.05,
                    colors: [Color(0x55DDF3F5), Colors.transparent],
                  ),
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: EventDetailSpacing.contentMaxWidth,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: EventDetailSpacing.pageHorizontal,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _EventDetailTopBar(onMore: widget.onMore),
                              EventSummaryCard(state: widget.state),
                              const _SectionHeader('\u65f6\u95f4\u5b89\u6392'),
                              EventScheduleCard(
                                state: widget.state,
                                onEditField: widget.onEditField,
                              ),
                              const _SectionHeader(
                                '\u8be6\u60c5\u4e0e\u5907\u6ce8',
                              ),
                              EventNoteCard(
                                state: widget.state,
                                onTap: () => widget.onEditField?.call(
                                  EventDetailField.note,
                                ),
                              ),
                              const _SectionHeader(
                                '\u72b6\u6001\u4e0e\u53c2\u4e0e',
                              ),
                              EventMetaGridCard(state: widget.state),
                              const SizedBox(height: 122),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: EventDetailActionBar(
          onEdit: widget.onEdit,
          onComplete: _handleComplete,
          isCompleting: _isCompleting,
        ),
      ),
    );
  }
}

class _EventDetailTopBar extends StatelessWidget {
  const _EventDetailTopBar({this.onMore});

  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: EventDetailSizes.topBarHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                tooltip: '\u8fd4\u56de',
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 22),
                color: EventDetailColors.primaryText,
              ),
            ),
          ),
          const Text(
            '\u65e5\u7a0b\u8be6\u60c5',
            style: EventDetailTextStyles.topBarTitle,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                tooltip: '\u66f4\u591a',
                padding: EdgeInsets.zero,
                onPressed: onMore,
                icon: const Icon(Icons.more_horiz_rounded, size: 26),
                color: EventDetailColors.primaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: EventDetailSpacing.sectionTop,
        bottom: EventDetailSpacing.sectionToCard,
      ),
      child: Text(label, style: EventDetailTextStyles.sectionTitle),
    );
  }
}
