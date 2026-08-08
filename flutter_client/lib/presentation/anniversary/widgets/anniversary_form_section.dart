import 'package:flutter/material.dart';

import '../anniversary_design_tokens.dart';

class AnniversaryFormSection extends StatelessWidget {
  const AnniversaryFormSection({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AnniversaryColors.cardBackground,
        borderRadius: BorderRadius.circular(AnniversarySizes.formCardRadius),
        boxShadow: AnniversaryShadows.card,
      ),
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    );
  }
}
