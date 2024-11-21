import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:mlkit_liveness/main.dart';

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
  bool headMovementDetected = false;

  // Instructions and progress
  final List<String> instructions = [
    "Blink your eyes",
    "Smile at the camera",
    "Turn your head left and right",
  ];
  int currentInstructionIndex = 0;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableLandmarks: true, // Optionally enable landmarks
        enableTracking: true, // Disable tracking for simplicity
        performanceMode: FaceDetectorMode.fast, // Use fast mode for better real-time performance
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
      setState(() {}); // Refresh the UI after the camera initializes
      _cameraController?.startImageStream(_processCameraImage);
    } catch (e) {
      debugPrint("Error initializing camera: $e");
    }
  }

  void _processCameraImage(CameraImage image) async {
    debugPrint('Processing camera image...');
    debugPrint('Current Instruction: ${instructions[currentInstructionIndex]}');
    debugPrint('Blink Detected: $blinkDetected');
    debugPrint('Smile Detected: $smileDetected');
    debugPrint('Head Movement Detected: $headMovementDetected');
    if (_isProcessing) return;

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
        rotation: _rotationFromCamera(_cameraController!.description.sensorOrientation),
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );

    try {
      final List<Face> faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        debugPrint('Faces detected: ${faces.length}');
        for (Face face in faces) {
          debugPrint('Bounding Box: ${face.boundingBox}');
          debugPrint('Left Eye Open Probability: ${face.leftEyeOpenProbability}');
          debugPrint('Right Eye Open Probability: ${face.rightEyeOpenProbability}');
          debugPrint('Number of faces detected: ${faces.length}');
          // Check instructions
          if (currentInstructionIndex == 0) {
            if (face.leftEyeOpenProbability != null &&
                face.rightEyeOpenProbability != null &&
                face.leftEyeOpenProbability! < 0.5 &&
                face.rightEyeOpenProbability! < 0.5) {
              blinkDetected = true;
            }
          } else if (currentInstructionIndex == 1) {
            if (face.smilingProbability != null &&
                face.smilingProbability! > 0.5) {
              smileDetected = true;
            }
          } else if (currentInstructionIndex == 2) {
            if (face.headEulerAngleY != null &&
                face.headEulerAngleY!.abs() > 15) {
              headMovementDetected = true;
            }
          }
        }

        // Move to the next instruction if the current one is completed
        if (blinkDetected && currentInstructionIndex == 0) {
          setState(() {
            currentInstructionIndex++;
          });
        } else if (smileDetected && currentInstructionIndex == 1) {
          setState(() {
            currentInstructionIndex++;
          });
        } else if (headMovementDetected && currentInstructionIndex == 2) {
          _cameraController?.stopImageStream();
          _showLivenessResult(true);
        }
      }
    } catch (e) {
      debugPrint("Error detecting faces: $e");
    } finally {
      _isProcessing = false;
    }
  }

  void _showLivenessResult(bool success) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(success ? "Liveness Confirmed" : "Liveness Failed"),
        content: Text(
            success ? "All liveness checks passed!" : "Liveness checks failed."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (success) {
                // Handle success action
              }
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
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
        title: const Text('Face Liveness Detection'),
      ),
      body: Stack(
        children: [
          if (_cameraController?.value.isInitialized ?? false)
            CameraPreview(_cameraController!)
          else
            const Center(child: CircularProgressIndicator()),

          // Instruction Overlay
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              color: Colors.black.withOpacity(0.5),
              padding: const EdgeInsets.all(16.0),
              child: Text(
                instructions[currentInstructionIndex],
                style: const TextStyle(color: Colors.white, fontSize: 18.0),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}