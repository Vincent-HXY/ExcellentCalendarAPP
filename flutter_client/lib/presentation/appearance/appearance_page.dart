import 'package:flutter/material.dart';

import '../../application/appearance/appearance_controller.dart';
import '../../native_contract/appearance/appearance_contract.dart';
import '../habit/habit_design.dart';

class AppearancePage extends StatelessWidget {
  const AppearancePage({required this.controller, super.key});
  final AppearanceController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: HabitDesign.background(context),
    appBar: AppBar(
      backgroundColor: HabitDesign.background(context),
      title: const Text('外观设置'),
    ),
    body: SafeArea(
      top: false,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          if (controller.phase == AppearancePhase.loading &&
              controller.token == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (controller.phase == AppearancePhase.error &&
              controller.token == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(controller.errorMessage ?? '外观设置加载失败'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: controller.load,
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                '习惯进度颜色',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text('从七种经过浅色和深色对比度验证的预设中选择。保存在本机，不会同步到云端。'),
              const SizedBox(height: 18),
              for (final token in HabitProgressColorToken.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Semantics(
                    button: true,
                    selected: controller.token == token,
                    label:
                        '${_label(token)}，${controller.token == token ? '已选中' : '未选中'}',
                    child: Material(
                      color: HabitDesign.surface(context),
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: controller.phase == AppearancePhase.updating
                            ? null
                            : () => controller.update(token),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 60),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: resolvedHabitTokenColor(
                                      context,
                                      token,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    _label(token),
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ),
                                if (controller.token == token)
                                  const Icon(Icons.check_circle_rounded),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (controller.errorMessage != null)
                Text(
                  controller.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          );
        },
      ),
    ),
  );
}

Color colorForHabitToken(HabitProgressColorToken? token) => switch (token) {
  HabitProgressColorToken.blue => const Color(0xFF2563EB),
  HabitProgressColorToken.indigo => const Color(0xFF4F46E5),
  HabitProgressColorToken.green => const Color(0xFF16803A),
  HabitProgressColorToken.orange => const Color(0xFFC2410C),
  HabitProgressColorToken.rose => const Color(0xFFBE123C),
  HabitProgressColorToken.purple => const Color(0xFF7E22CE),
  HabitProgressColorToken.teal => const Color(0xFF0F8C91),
  null => const Color(0xFF546E7A),
};

Color resolvedHabitTokenColor(
  BuildContext context,
  HabitProgressColorToken token,
) => ColorScheme.fromSeed(
  seedColor: colorForHabitToken(token),
  brightness: Theme.of(context).brightness,
).primary;

String _label(HabitProgressColorToken token) => switch (token) {
  HabitProgressColorToken.teal => '青绿',
  HabitProgressColorToken.blue => '蓝色',
  HabitProgressColorToken.indigo => '靛蓝',
  HabitProgressColorToken.green => '绿色',
  HabitProgressColorToken.orange => '橙色',
  HabitProgressColorToken.rose => '玫红',
  HabitProgressColorToken.purple => '紫色',
};
