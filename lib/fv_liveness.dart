import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:mlkit_liveness/main.dart';

import 'dart:io';

class FaceLivenessScreen extends StatefulWidget {
  const FaceLivenessScreen({super.key});

  @override
  _FaceLivenessScreenState createState() => _FaceLivenessScreenState();
}

class _FaceLivenessScreenState extends State<FaceLivenessScreen> {
  CameraController? _cameraController;
  late FaceDetector _faceDetector;
  bool _isProcessing = false;
  bool blinkDetected = false;
  bool smileDetected = false;
  bool turnLeftDetected = false;
  bool turnRightDetected = false;

  String capturedPhotoPath = '';

  bool isWaiting = false;
  bool isComplete = false;

  // Instructions and progress
  final List<String> instructions = [
    "Blink your eyes",
    "Smile at the camera",
    "Turn your head right",
    "Turn your head left",
    "Press Continue"
  ];
  int currentInstructionIndex = 0;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableLandmarks: true,
        enableTracking: true,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
  }

  InputImageRotation _rotationFromCamera(int sensorOrientation) {
    switch (sensorOrientation) {
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      case 0:
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  void _initializeCamera() async {
    try {
      _cameraController = CameraController(cameras![1], ResolutionPreset.high);
      await _cameraController?.initialize();
      setState(() {});
      _cameraController?.startImageStream(_processCameraImage);
    } catch (e) {
      debugPrint("Error initializing camera: $e");
    }
  }

  void _processCameraImage(CameraImage image) async {
    if (_isProcessing || isWaiting) return;

    _isProcessing = true;

    final WriteBuffer allBytes = WriteBuffer();
    for (Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final InputImage inputImage = InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: _rotationFromCamera(
            _cameraController!.description.sensorOrientation),
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );

    try {
      final List<Face> faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        for (Face face in faces) {
          // Blink detection logic
          if (currentInstructionIndex == 0) {
            if (face.leftEyeOpenProbability != null &&
                face.rightEyeOpenProbability != null &&
                face.leftEyeOpenProbability! < 0.05 &&
                face.rightEyeOpenProbability! < 0.05) {
              blinkDetected = true;
            }
          }

          // Smile detection logic
          if (currentInstructionIndex == 1) {
            if (face.smilingProbability != null &&
                face.smilingProbability! > 0.7) {
              smileDetected = true;
            }
          }

          // Turn left detection logic
          if (currentInstructionIndex == 2) {
            if (face.headEulerAngleY != null && face.headEulerAngleY! < -35) {
              turnLeftDetected = true;
            }
          }

          // Turn right detection logic
          if (currentInstructionIndex == 3) {
            if (face.headEulerAngleY != null && face.headEulerAngleY! > 35) {
              turnRightDetected = true;
            }
          }
        }

        // Update instructions based on detections
        if ((blinkDetected && currentInstructionIndex == 0) ||
            (smileDetected && currentInstructionIndex == 1) ||
            (turnLeftDetected && currentInstructionIndex == 2)) {
          setState(() {
            isWaiting = true; // Show "Please wait..." text
          });

          await Future.delayed(const Duration(seconds: 2)); // Wait 2 seconds

          setState(() {
            isWaiting = false; // Reset waiting state
            currentInstructionIndex++;
          });

          if (currentInstructionIndex == 2 && smileDetected) {
            _capturePhoto(); // Automatically take a photo after the second instruction
          }
        } else if (turnRightDetected && currentInstructionIndex == 3) {
          _cameraController?.stopImageStream();
          setState(() {
            currentInstructionIndex++;
            isComplete = true; // Mark as complete after all steps
          });
        }
      }
    } catch (e) {
      debugPrint("Error detecting faces: $e");
    } finally {
      _isProcessing = false;
    }
  }

  void _capturePhoto() async {
    try {
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        final XFile photo = await _cameraController!.takePicture();
        debugPrint('Photo captured: ${photo.path}');

        // Save the photo in a variable
        capturedPhotoPath = photo.path;

        // You can perform additional actions with the photo path, e.g., display it or upload it.
      }
    } catch (e) {
      debugPrint("Error capturing photo: $e");
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Face Liveness Detection',
          style: TextStyle(
            fontWeight: FontWeight.bold, // Set the font weight to bold
          ),
        ),
      ),
      body: Stack(
        children: [
          // Camera preview
          if (_cameraController?.value.isInitialized ?? false)
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(-1.0, 1.0, 1.0),
              child: CameraPreview(_cameraController!),
            )
          else
            const Center(child: CircularProgressIndicator()),

          // Custom painter for cutout
          Opacity(
            opacity: 1, // Opacity for the outer area
            child: CustomPaint(
              size: MediaQuery.of(context).size,
              painter: CutoutPainter(),
            ),
          ),

          // Instruction and progress bar overlay
          // Instructions and progress bar overlay
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isWaiting
                      ? "Please wait..."
                      : instructions[currentInstructionIndex],
                  style: const TextStyle(
                      color: Color(0xFF005D99),
                      fontSize: 18.0,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8.0),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: LinearProgressIndicator(
                    value:
                        (currentInstructionIndex == instructions.length - 1 &&
                                !isWaiting)
                            ? 1.0
                            : (currentInstructionIndex + (isWaiting ? 1 : 0)) /
                                instructions.length,
                    backgroundColor: const Color(0xFFC2E7FF),
                    color: const Color(0xFF005D99),
                    minHeight: 8.0,
                  ),
                ),
              ],
            ),
          ),

          // "Continue" button at the bottom
          Positioned(
            bottom: 20,
            left: 8,
            right: 8,
            child: SizedBox(
              width: 360,
              height: 40,
              child: ElevatedButton(
                onPressed: isComplete
                    ? () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => ImageDisplayScreen(
                              imagePath: capturedPhotoPath,
                            ),
                          ),
                        );
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  foregroundColor: const Color(0xFFC2E7FF),
                  backgroundColor: const Color(0xFF005D99),
                  textStyle: const TextStyle(fontSize: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  "Continue",
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ImageDisplayScreen extends StatelessWidget {
  final String imagePath;

  const ImageDisplayScreen({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Captured Image'),
      ),
      body: Center(
        child: imagePath.isNotEmpty
            ? Image.file(File(imagePath)) // Display the captured image
            : const Text('No image captured.'),
      ),
    );
  }
}

// CustomPainter for drawing the transparent cutout
class CutoutPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Outer rectangle that covers the entire screen
    final outerRect = Offset.zero & size;

    // Define the position and size of the oval
    const double ovalWidth = 250; // Width of the oval
    const double ovalHeight = 300; // Height of the oval
    final double left =
        (size.width - ovalWidth) / 2; // Center the oval horizontally

    // Position the oval in the middle of the screen
    final double top = (size.height - ovalHeight) / 2;

    // Define the oval area
    final Rect ovalRect = Rect.fromLTWH(left, top, ovalWidth, ovalHeight);

    // Paint the outer area with a semi-transparent color
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Draw the outer area excluding the oval
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(outerRect), // Outer area
        Path()..addOval(ovalRect), // Oval area
      ),
      paint,
    );

    // Draw border around the oval
    final borderPaint = Paint()
      ..color = const Color(0xFF005D99)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0;

    canvas.drawOval(ovalRect, borderPaint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return false; // No need to repaint unless the oval's position or size changes
  }
}
