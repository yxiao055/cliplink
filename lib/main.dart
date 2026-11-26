import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'app_controller.dart';
import 'ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.cream,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  final controller = AppController();
  await controller.bootstrap();
  runApp(ClipLinkApp(controller: controller));
}
