import 'package:flutter/material.dart';

import '../../../native_contract/search/search_text_contract.dart';
import '../search_design_tokens.dart';

class HighlightedSearchText extends StatelessWidget {
  const HighlightedSearchText({
    required this.text,
    required this.normalizedKeyword,
    required this.highlightColor,
    this.style,
    this.maxLines,
    this.overflow = TextOverflow.ellipsis,
    this.prefixTruncated = false,
    this.suffixTruncated = false,
    super.key,
  });

  final String text;
  final String normalizedKeyword;
  final Color highlightColor;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;
  final bool prefixTruncated;
  final bool suffixTruncated;

  @override
  Widget build(BuildContext context) {
    final visible =
        '${prefixTruncated ? '…' : ''}$text${suffixTruncated ? '…' : ''}';
    final ranges = visibleSearchMatchRanges(visible, normalizedKeyword);
    final colors = SearchDesignTokens.highlightColors(
      Theme.of(context).colorScheme,
      highlightColor,
    );
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final range in ranges) {
      if (range.start > offset) {
        spans.add(TextSpan(text: visible.substring(offset, range.start)));
      }
      spans.add(
        TextSpan(
          text: visible.substring(range.start, range.end),
          style: TextStyle(
            backgroundColor: colors.background,
            color: colors.foreground,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      offset = range.end;
    }
    if (offset < visible.length) {
      spans.add(TextSpan(text: visible.substring(offset)));
    }
    return Semantics(
      label: visible,
      child: ExcludeSemantics(
        child: Text.rich(
          TextSpan(
            style: style,
            children: spans.isEmpty ? [TextSpan(text: visible)] : spans,
          ),
          maxLines: maxLines,
          overflow: overflow,
        ),
      ),
    );
  }
}

List<TextRange> visibleSearchMatchRanges(String text, String keyword) {
  if (text.isEmpty || SearchTextContract.isBlank(keyword)) return const [];
  final scalars = <_Scalar>[];
  var offset = 0;
  for (final rune in text.runes) {
    final width = rune > 0xFFFF ? 2 : 1;
    scalars.add(_Scalar(_asciiFold(rune), offset, offset + width));
    offset += width;
  }
  final folded = scalars.map((value) => value.rune).toList(growable: false);
  final tokens = SearchTextContract.analyze(
    keyword,
  ).normalizedDisplay.split(' ').where((value) => value.isNotEmpty);
  final ranges = <TextRange>[];
  for (final token in tokens) {
    final needle = token.runes.map(_asciiFold).toList(growable: false);
    if (needle.isEmpty || needle.length > folded.length) continue;
    for (var start = 0; start <= folded.length - needle.length; start++) {
      var matches = true;
      for (var index = 0; index < needle.length; index++) {
        if (folded[start + index] != needle[index]) {
          matches = false;
          break;
        }
      }
      if (matches) {
        ranges.add(
          TextRange(
            start: scalars[start].start,
            end: scalars[start + needle.length - 1].end,
          ),
        );
      }
    }
  }
  if (ranges.isEmpty) return const [];
  ranges.sort(
    (a, b) => a.start != b.start
        ? a.start.compareTo(b.start)
        : a.end.compareTo(b.end),
  );
  final merged = <TextRange>[];
  for (final range in ranges) {
    if (merged.isEmpty || range.start > merged.last.end) {
      merged.add(range);
    } else if (range.end > merged.last.end) {
      merged[merged.length - 1] = TextRange(
        start: merged.last.start,
        end: range.end,
      );
    }
  }
  return List.unmodifiable(merged);
}

int _asciiFold(int rune) => rune >= 65 && rune <= 90 ? rune + 32 : rune;

class _Scalar {
  const _Scalar(this.rune, this.start, this.end);
  final int rune;
  final int start;
  final int end;
}
