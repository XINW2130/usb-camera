import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'services/camera_service.dart';
import 'services/usb_service.dart';
import 'services/media_gallery_service.dart';
import 'services/locale_service.dart';
import 'screens/camera_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final localeService = LocaleService();
  await localeService.load();
  runApp(USBCameraApp(localeService: localeService));
}

class USBCameraApp extends StatelessWidget {
  final LocaleService localeService;
  const USBCameraApp({super.key, required this.localeService});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleService>.value(value: localeService),
        Provider<CameraService>(create: (_) => CameraService()),
        Provider<USBService>(create: (_) => USBService()),
        ChangeNotifierProvider<MediaGalleryService>(
          create: (_) => MediaGalleryService(),
        ),
      ],
      child: Consumer<LocaleService>(
        builder: (context, l10n, _) {
          return MaterialApp(
            title: l10n.t('app_title'),
            debugShowCheckedModeBanner: false,
            locale: l10n.locale,
            supportedLocales: const [
              Locale('en'),
              Locale('zh'),
            ],
            localizationsDelegates: const [
              DefaultMaterialLocalizations.delegate,
              DefaultWidgetsLocalizations.delegate,
            ],
            theme: AppTheme.darkTheme,
            home: const CameraScreen(),
          );
        },
      ),
    );
  }
}
