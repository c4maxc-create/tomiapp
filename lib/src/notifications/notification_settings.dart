import 'package:flutter/material.dart';
import '../accounts/account_widgets.dart';
import 'push_controller.dart';

class NotificationSettingsPage extends StatelessWidget {
  const NotificationSettingsPage({super.key, required this.controller});
  final PushController controller;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('الإشعارات')),
    body: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SwitchListTile(
            key: const Key('push-enabled'),
            title: const Text('إشعارات المحادثات والمكالمات'),
            subtitle: const Text(
              'تنبيه بالرسائل والمكالمات الواردة عندما يكون التطبيق بالخلفية.',
            ),
            value:
                controller.enabled &&
                controller.permissionGranted &&
                controller.configured,
            onChanged: controller.busy || !controller.configured
                ? null
                : controller.setEnabled,
          ),
          const SizedBox(height: 10),
          const Text(
            'لحماية خصوصيتك، الإشعار ما يعرض نص الرسالة أو محتوى الصورة والتسجيل.',
          ),
          if (!controller.configured && !controller.busy)
            const AccountErrorMessage(
              'الإشعارات غير متاحة حاليًا في هذه النسخة.',
            ),
          if (controller.error != null) AccountErrorMessage(controller.error!),
          if (controller.busy)
            const Center(child: CircularProgressIndicator())
          else
            TextButton.icon(
              onPressed: controller.connect,
              icon: const Icon(Icons.refresh),
              label: const Text('تحديث حالة الإشعارات'),
            ),
        ],
      ),
    ),
  );
}
