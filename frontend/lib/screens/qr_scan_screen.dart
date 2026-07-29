import 'package:flutter/material.dart';
import 'package:remix_icons_flutter/remixicon_ids.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/harmonyos_platform.dart';
import '../utils/platform_detector.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController controller = MobileScannerController();
  bool _isScanned = false;
  bool _isOhosScanning = false;

  @override
  void initState() {
    super.initState();
    if (PlatformDetector.isOhos) {
      _scanOnHarmonyOS();
    }
  }

  Future<void> _scanOnHarmonyOS() async {
    if (_isOhosScanning) return;
    _isOhosScanning = true;
    final result = await HarmonyosPlatform.scanQrCode();
    if (mounted) {
      _isOhosScanning = false;
      if (result != null && result.isNotEmpty) {
        Navigator.pop(context, result);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (PlatformDetector.isOhos) {
      return Scaffold(
        appBar: AppBar(title: const Text('Scan QR Code')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              const Text('Opening scanner...'),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(RemixIcon.refreshLine),
                label: const Text('Retry'),
                onPressed: _scanOnHarmonyOS,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        actions: [
          IconButton(
            icon: ValueListenableBuilder<MobileScannerState>(
              valueListenable: controller,
              builder: (context, state, child) {
                switch (state.torchState) {
                  case TorchState.off:
                    return const Icon(RemixIcon.flashlightLine, color: Colors.grey);
                  case TorchState.on:
                    return const Icon(RemixIcon.flashlightLine, color: Colors.yellow);
                  case TorchState.unavailable:
                  case TorchState.auto:
                    return const Icon(RemixIcon.flashlightLine, color: Colors.grey);
                }
              },
            ),
            onPressed: () => controller.toggleTorch(),
          ),
          IconButton(
            icon: ValueListenableBuilder<MobileScannerState>(
              valueListenable: controller,
              builder: (context, state, child) {
                switch (state.cameraDirection) {
                  case CameraFacing.front:
                    return const Icon(RemixIcon.cameraLine);
                  case CameraFacing.back:
                    return const Icon(RemixIcon.cameraLine);
                }
              },
            ),
            onPressed: () => controller.switchCamera(),
          ),
        ],
      ),
      body: MobileScanner(
        controller: controller,
        onDetect: (capture) {
          if (_isScanned) return;
          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            if (barcode.rawValue != null) {
              _isScanned = true;
              Navigator.pop(context, barcode.rawValue);
              break;
            }
          }
        },
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
