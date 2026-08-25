import 'package:flutter/material.dart';

import '../auth_design_tokens.dart';

/// Minimal page scaffold shared by the auth/profile pages.
class AuthPageScaffold extends StatelessWidget {
  const AuthPageScaffold({
    required this.title,
    required this.child,
    this.actions = const <Widget>[],
    this.showBack = true,
    this.resizeToAvoidBottomInset = true,
    super.key,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final bool showBack;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuthDesignTokens.pageBackground,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: AppBar(
        backgroundColor: AuthDesignTokens.pageBackground,
        elevation: 0,
        leading: showBack
            ? IconButton(
                tooltip: '返回',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              )
            : null,
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: AuthDesignTokens.textPrimary,
          ),
        ),
        actions: actions,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: child,
        ),
      ),
    );
  }
}
