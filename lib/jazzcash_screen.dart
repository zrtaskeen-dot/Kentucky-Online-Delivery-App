import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class JazzCashScreen extends StatefulWidget {
  final double amount;

  const JazzCashScreen({super.key, required this.amount});

  @override
  State<JazzCashScreen> createState() => _JazzCashScreenState();
}

class _JazzCashScreenState extends State<JazzCashScreen> {
  late WebViewController controller;

  @override
  void initState() {
    super.initState();

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Debug logs (important)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            debugPrint("Loading: $url");
          },
          onPageFinished: (url) {
            debugPrint("Loaded: $url");
          },
        ),
      )
      // ✅ IMPORTANT: open YOUR PHP page (not JazzCash directly)
      ..loadRequest(
        Uri.parse(
          "https://neglector-void-wharf.ngrok-free.dev/jazzcash/in.html?amount=${widget.amount}",
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("JazzCash Payment")),
      body: WebViewWidget(controller: controller),
    );
  }
}
