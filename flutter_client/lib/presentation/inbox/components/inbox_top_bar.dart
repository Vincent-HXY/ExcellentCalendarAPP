import 'package:flutter/material.dart';

import '../inbox_design_tokens.dart';

class InboxTopBar extends StatelessWidget {
  const InboxTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: InboxSizes.topBarHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 6, 20, 0),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Menu',
              onPressed: () {},
              icon: const Icon(Icons.menu_rounded),
              color: Colors.black87,
              iconSize: InboxSizes.topBarIcon,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                width: InboxSizes.topBarIconButton,
                height: InboxSizes.topBarIconButton,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                '日程',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: InboxTextStyles.headerTitle,
              ),
            ),
            IconButton(
              tooltip: 'More',
              onPressed: () {},
              icon: const Icon(Icons.more_vert_rounded),
              color: Colors.black87,
              iconSize: InboxSizes.topBarIcon,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                width: InboxSizes.topBarIconButton,
                height: InboxSizes.topBarIconButton,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
