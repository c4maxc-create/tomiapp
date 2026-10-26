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
            title: const Text('تنبيهات TOMI'),
            subtitle: const Text(
              'تنبيه بالرسائل والمكالمات والمتابعين والتفاعلات الجديدة.',
            ),
            value:
                controller.enabled &&
                controller.permissionGranted &&
                controller.configured &&
                controller.clientReady &&
                controller.registeredToken != null,
            onChanged: controller.busy ? null : controller.setEnabled,
          ),
          if (controller.checked) ...[
            ListTile(
              leading: Icon(
                controller.clientReady
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
              ),
              title: Text(
                controller.clientReady
                    ? 'إعداد التطبيق جاهز'
                    : 'إعداد إشعارات التطبيق غير مكتمل',
              ),
            ),
            ListTile(
              leading: Icon(
                controller.configured
                    ? Icons.check_circle_outline
                    : Icons.cloud_off_outlined,
              ),
              title: Text(
                controller.configured
                    ? 'خدمة الخادم جاهزة'
                    : 'خدمة إشعارات الخادم غير مفعّلة',
              ),
            ),
          ],
          const SizedBox(height: 10),
          const Text(
            'لحماية خصوصيتك، الإشعار ما يعرض نص الرسالة أو محتوى الصورة والتسجيل.',
          ),
          if (!controller.configured &&
              !controller.busy &&
              controller.error == null)
            const AccountErrorMessage(
              'تنبيهات الهاتف تحتاج إلى تفعيل الخدمة؛ الإشعارات داخل التطبيق متاحة.',
            ),
          if (controller.error != null) AccountErrorMessage(controller.error!),
          if (controller.clientReady &&
              !controller.permissionGranted &&
              !controller.busy)
            TextButton.icon(
              onPressed: controller.openSystemSettings,
              icon: const Icon(Icons.open_in_new),
              label: const Text('فتح إعدادات إشعارات الهاتف'),
            ),
          if (controller.configured &&
              controller.permissionGranted &&
              controller.enabled &&
              controller.registeredToken != null)
            const ListTile(
              leading: Icon(
                Icons.check_circle_outline,
                color: Colors.greenAccent,
              ),
              title: Text('الإشعارات مفعّلة على هذا الهاتف'),
            ),
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
