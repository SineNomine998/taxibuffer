import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_state.dart';
import 'package:mobile_app/core/notifications/notification_service.dart';
import 'package:mobile_app/features/queue/queue_location_tracker.dart';
import 'app.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mobile_app/features/queue/queue_state.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('nl');

  await Firebase.initializeApp();

  await NotificationService.instance.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => QueueState()),
        ChangeNotifierProvider.value(value: authGateState),
        ChangeNotifierProvider.value(value: privacyGateState),
        ChangeNotifierProvider.value(value: termsGateState),
        ChangeNotifierProvider(create: (_) => QueueLocationTracker()),
      ],
      child: const App(),
    ),
  );
}
