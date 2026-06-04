// 文件作用：Inbox 首页悬浮新增按钮，触发进入新建日程页面。
// 设计边界：只负责点击入口和视觉样式，不负责创建日程。
import 'package:flutter/material.dart';

class AddTaskButton extends StatelessWidget {
  const AddTaskButton({required this.onPressed, super.key});

  // 数据块作用：由父页面传入的新增入口回调，当前用于打开新建日程页面。
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // 函数作用：绘制圆形悬浮按钮，并把点击事件交还给父页面处理。
    return Material(
      color: const Color(0xFF38B9C5),
      shape: const CircleBorder(),
      elevation: 8,
      shadowColor: const Color(0x5538B9C5),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const SizedBox(
          width: 58,
          height: 58,
          child: Icon(Icons.add_rounded, color: Colors.white, size: 34),
        ),
      ),
    );
  }
}
