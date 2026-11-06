import 'src/experience/performance_monitor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PerformanceMonitor.instance.install();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF10131E),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const TomiApp());
}
