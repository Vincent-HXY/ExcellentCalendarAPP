import 'package:flutter/material.dart';

import '../../../application/anniversary/anniversary_list_controller.dart';
import '../anniversary_design_tokens.dart';

class AnniversaryFilterBar extends StatelessWidget {
  const AnniversaryFilterBar({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final AnniversaryListFilter selected;
  final ValueChanged<AnniversaryListFilter> onSelected;

  static const _labels = {
    AnniversaryListFilter.all: '所有',
    AnniversaryListFilter.anniversary: '纪念日',
    AnniversaryListFilter.countdown: '倒数日',
    AnniversaryListFilter.birthday: '生日',
    AnniversaryListFilter.holiday: '节日',
  };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in AnniversaryListFilter.values) ...[
            Semantics(
              selected: selected == filter,
              button: true,
              label: '筛选：${_labels[filter]}',
              child: ChoiceChip(
                key: ValueKey('anniversary-filter-${filter.name}'),
                label: Text(_labels[filter]!),
                selected: selected == filter,
                onSelected: (_) => onSelected(filter),
                showCheckmark: false,
                selectedColor: AnniversaryColors.selectedChip,
                backgroundColor: Colors.transparent,
                side: BorderSide.none,
                labelStyle: TextStyle(
                  color: selected == filter
                      ? AnniversaryColors.primaryTeal
                      : AnniversaryColors.secondaryText,
                  fontSize: 14,
                  fontWeight: selected == filter
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
            if (filter != AnniversaryListFilter.values.last)
              const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}
