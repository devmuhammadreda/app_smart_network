import 'package:app_smart_network/app_smart_network.dart';
import 'package:flutter/material.dart';

import 'src/pages/home_page.dart';

// ============================================================================
// ENTRY POINT
// ============================================================================

void main() {
  // ① Initialize the package once before runApp().
  //    Pass your base URL and any global config here.
  AppSmartNetworkService.initialize(
    NetworkConfig(
      baseUrl: 'https://jsonplaceholder.typicode.com',

      // Called automatically when the server returns HTTP 401.
      onUnauthorized: () {
        AppSmartNetworkService.instance.removeAuthToken();
        // In a real app: navigate to the login screen.
        debugPrint('Session expired – redirect to login.');
      },

      // Extend default headers (e.g. an API key).
      // defaultHeaders: {'X-Api-Key': 'your-key'},

      // Only enable in debug builds.
      // allowBadCertificate: kDebugMode,
    ),
  );

  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'app_smart_network example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
