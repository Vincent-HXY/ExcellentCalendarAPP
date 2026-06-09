import 'package:flutter/material.dart';

import 'picker_design_tokens.dart';

class PickerWheelColumn extends StatefulWidget {
  const PickerWheelColumn({
    required this.itemCount,
    required this.selectedIndex,
    required this.labelBuilder,
    required this.onSelectedItemChanged,
    this.width,
    this.looping = false,
    super.key,
  });

  final int itemCount;
  final int selectedIndex;
  final String Function(int index) labelBuilder;
  final ValueChanged<int> onSelectedItemChanged;
  final double? width;
  final bool looping;

  @override
  State<PickerWheelColumn> createState() => _PickerWheelColumnState();
}

class _PickerWheelColumnState extends State<PickerWheelColumn> {
  static const _loopCenter = 10000;

  late final FixedExtentScrollController _controller;
  late int _selectedValue;

  @override
  void initState() {
    super.initState();
    _selectedValue = _normalize(widget.selectedIndex);
    _controller = FixedExtentScrollController(
      initialItem: widget.looping
          ? _loopInitialIndex(_selectedValue)
          : _selectedValue,
    );
  }

  @override
  void didUpdateWidget(PickerWheelColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount != widget.itemCount &&
        _selectedValue >= widget.itemCount) {
      _selectedValue = widget.itemCount - 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) {
          return;
        }
        _controller.jumpToItem(
          widget.looping ? _loopInitialIndex(_selectedValue) : _selectedValue,
        );
      });
      return;
    }

    final externalValue = _normalize(widget.selectedIndex);
    if (oldWidget.selectedIndex != widget.selectedIndex &&
        externalValue != _selectedValue) {
      _selectedValue = externalValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int _normalize(int index) {
    if (widget.itemCount <= 0) {
      return 0;
    }
    return ((index % widget.itemCount) + widget.itemCount) % widget.itemCount;
  }

  int _loopInitialIndex(int value) {
    return _loopCenter - (_loopCenter % widget.itemCount) + value;
  }

  void _handleSelectedItemChanged(int rawIndex) {
    final value = _normalize(rawIndex);
    if (value != _selectedValue) {
      setState(() {
        _selectedValue = value;
      });
    }
    widget.onSelectedItemChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: PickerSizes.wheelHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned(
            left: 0,
            right: 0,
            top: (PickerSizes.wheelHeight - PickerSizes.wheelItemExtent) / 2,
            child: Divider(
              height: 1,
              thickness: 1,
              color: PickerColors.divider,
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: (PickerSizes.wheelHeight - PickerSizes.wheelItemExtent) / 2,
            child: Divider(
              height: 1,
              thickness: 1,
              color: PickerColors.divider,
            ),
          ),
          ListWheelScrollView.useDelegate(
            controller: _controller,
            itemExtent: PickerSizes.wheelItemExtent,
            diameterRatio: 1.6,
            overAndUnderCenterOpacity: 0.56,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: _handleSelectedItemChanged,
            childDelegate: widget.looping
                ? ListWheelChildLoopingListDelegate(
                    children: List.generate(widget.itemCount, _buildItem),
                  )
                : ListWheelChildBuilderDelegate(
                    childCount: widget.itemCount,
                    builder: (context, index) {
                      if (index < 0 || index >= widget.itemCount) {
                        return null;
                      }
                      return _buildItem(index);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(int index) {
    final value = _normalize(index);
    final isSelected = value == _selectedValue;
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          widget.labelBuilder(value),
          maxLines: 1,
          softWrap: false,
          style: isSelected
              ? PickerTextStyles.wheelSelected
              : PickerTextStyles.wheelUnselected,
        ),
      ),
    );
  }
}
