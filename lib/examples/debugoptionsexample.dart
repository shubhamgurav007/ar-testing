import 'package:ar_flutter_plugin/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_anchor_manager.dart';
import 'package:flutter/material.dart';
import 'package:ar_flutter_plugin/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin/models/ar_hittest_result.dart';
import 'package:logger/web.dart';
import 'package:vector_math/vector_math_64.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class DebugOptionsWidget extends StatefulWidget {
  DebugOptionsWidget({Key? key}) : super(key: key);
  @override
  _DebugOptionsWidgetState createState() => _DebugOptionsWidgetState();
}

class _DebugOptionsWidgetState extends State<DebugOptionsWidget> {
  ARSessionManager? arSessionManager;
  ARObjectManager? arObjectManager;
  bool _showFeaturePoints = false;
  bool _showPlanes = false;
  bool _showWorldOrigin = false;
  bool _showAnimatedGuide = true;
  String _planeTexturePath = "Images/triangle.png";
  bool _handleTaps = false;

  List<PlaneData> collectedPlanes = [];

  @override
  void dispose() {
    super.dispose();
    arSessionManager?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Debug Options')),
      body: Container(
        child: Stack(
          children: [
            ARView(
              onARViewCreated: onARViewCreated,
              planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
              showPlatformType: true,
            ),
            Align(
              alignment: FractionalOffset.bottomRight,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.5,
                color: Color(0xFFFFFFF).withOpacity(0.5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      title: const Text('Feature Points'),
                      value: _showFeaturePoints,
                      onChanged: (bool value) {
                        setState(() {
                          _showFeaturePoints = value;
                          updateSessionSettings();
                        });
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Planes'),
                      value: _showPlanes,
                      onChanged: (bool value) {
                        setState(() {
                          _showPlanes = value;
                          updateSessionSettings();
                        });
                      },
                    ),
                    SwitchListTile(
                      title: const Text('World Origin'),
                      value: _showWorldOrigin,
                      onChanged: (bool value) {
                        setState(() {
                          _showWorldOrigin = value;
                          updateSessionSettings();
                        });
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Handle Taps'),
                      value: _handleTaps,
                      onChanged: (bool value) {
                        setState(() {
                          _handleTaps = value;
                          updateSessionSettings();
                        });
                      },
                    ),
                    ElevatedButton(
                      onPressed: () {
                        _calculateRoom();
                      },
                      child: Text("Calculate Room"),
                    ),
                    if (collectedPlanes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          "Captured ${collectedPlanes.length} planes",
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void onARViewCreated(
    ARSessionManager arSessionManager,
    ARObjectManager arObjectManager,
    ARAnchorManager arAnchorManager,
    ARLocationManager arLocationManager,
  ) {
    this.arSessionManager = arSessionManager;
    this.arObjectManager = arObjectManager;

    this.arSessionManager!.onInitialize(
      showFeaturePoints: _showFeaturePoints,
      showPlanes: _showPlanes,
      customPlaneTexturePath: _planeTexturePath,
      showWorldOrigin: _showWorldOrigin,
      showAnimatedGuide: _showAnimatedGuide,
      handleTaps: _handleTaps,
    );
    this.arObjectManager!.onInitialize();

    this.arSessionManager!.onPlaneOrPointTap = onPlaneOrPointTapped;
  }

  void updateSessionSettings() {
    this.arSessionManager!.onInitialize(
      showFeaturePoints: _showFeaturePoints,
      showPlanes: _showPlanes,
      customPlaneTexturePath: _planeTexturePath,
      showWorldOrigin: _showWorldOrigin,
      handleTaps: _handleTaps,
    );
  }

  void onPlaneOrPointTapped(List<ARHitTestResult> hitTestResults) {
    Logger().e("P111 hitTestResults:");
    var planeHit = hitTestResults.firstWhere(
      (hit) => hit.type == ARHitTestResultType.plane,
      orElse: () =>
          ARHitTestResult(ARHitTestResultType.undefined, 0, Matrix4.zero()),
    );

    if (planeHit.type != ARHitTestResultType.undefined) {
      // Extract translation and rotation from Matrix4
      var matrix = planeHit.worldTransform;
      var position = matrix.getTranslation();
      var rotation = Quaternion.fromRotation(matrix.getRotation());

      // Note: ARHitTestResult might not give us the plane extents directly.
      // We might need to listen to anchors or assume a default size for visualization/logic if we only have a point on plane.
      // For now, we'll store it. ideally we'd get the anchor ID and look it up.

      setState(() {
        collectedPlanes.add(
          PlaneData(
            id: "plane_${collectedPlanes.length}",
            position: position,
            rotation: Vector4(rotation.x, rotation.y, rotation.z, rotation.w),
            extents: Vector2(1.0, 1.0), // Placeholder extents
          ),
        );
      });

      Logger().w("P111 Plane added: ${collectedPlanes}");
    }
  }

  Future<void> _calculateRoom() async {
    if (collectedPlanes.isEmpty) {
      Logger().e("P111 No planes collected!");
      return;
    }

    RoomCalculator calculator = RoomCalculator();
    String jsonOutput = calculator.processPlanes(collectedPlanes);
    Logger().f("P111 Room Output: $jsonOutput");

    try {
      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
        // If standard Download dir doesn't exist or we can't write to it, fallback might be needed,
        // but for now we try this as requested.
        if (!await directory.exists()) {
          // Try fallback to what the plugin gives us if hardcoded path fails checks
          directory = await getExternalStorageDirectory();
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      // Ensure directory exists (Downloads should, but good practice)
      if (directory != null && !await directory.exists()) {
        // We can't create Downloads root, but we can check if it exists.
        // If it's app specific, we can create.
        // For system Downloads, it should exist.
      }

      // Add timestamp to filename to avoid overwrites or just keep room_data
      final file = File('${directory!.path}/room_data.json');
      await file.writeAsString(jsonOutput);
      Logger().f("P111 Saved to file: ${file.path}");

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Saved to ${file.path}")));
    } catch (e) {
      Logger().e("P111 Error saving file: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error saving to file: $e")));
    }
  }
}

// --- Logic Classes ---

class PlaneData {
  String id;
  Vector3 position;
  Vector4 rotation; // Quaternion
  Vector2 extents; // Width, Height

  PlaneData({
    required this.id,
    required this.position,
    required this.rotation,
    required this.extents,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'position': {'x': position.x, 'y': position.y, 'z': position.z},
    'rotation': {
      'x': rotation.x,
      'y': rotation.y,
      'z': rotation.z,
      'w': rotation.w,
    },
    'extents': {'width': extents.x, 'height': extents.y},
  };
}

class RoomCalculator {
  static const double _cornerDistanceThreshold = 0.5; // Meters

  String processPlanes(List<PlaneData> planes) {
    List<_WallSegment> walls = [];
    for (var plane in planes) {
      walls.add(_createWallSegment(plane));
    }

    // Isolate vertical planes?
    // Assuming user only tapped walls or we filter by rotation if needed.

    List<Map<String, dynamic>> corners = [];
    for (int i = 0; i < walls.length; i++) {
      for (int j = i + 1; j < walls.length; j++) {
        Vector3? intersection = _findIntersection(walls[i], walls[j]);
        if (intersection != null) {
          corners.add({
            'wall_id_1': walls[i].id,
            'wall_id_2': walls[j].id,
            'position': {
              'x': intersection.x,
              'y': intersection.y,
              'z': intersection.z,
            },
          });
        }
      }
    }

    List<Map<String, dynamic>> distances = [];
    for (int i = 0; i < walls.length; i++) {
      for (int j = i + 1; j < walls.length; j++) {
        double dist = walls[i].center.distanceTo(walls[j].center);
        distances.add({
          'from': walls[i].id,
          'to': walls[j].id,
          'distance': dist,
        });
      }
    }

    var output = {
      'walls': walls.map((w) => w.toJson()).toList(),
      'corners': corners,
      'distances': distances,
      'valid_room': corners.length >= 3,
    };

    return jsonEncode(output);
  }

  _WallSegment _createWallSegment(PlaneData plane) {
    Matrix3 rotMat = Matrix3.copy(
      Quaternion(
        plane.rotation.x,
        plane.rotation.y,
        plane.rotation.z,
        plane.rotation.w,
      ).asRotationMatrix(),
    );
    Vector3 right = rotMat.transform(Vector3(1, 0, 0));

    Vector3 start = plane.position + (right * (plane.extents.x / 2));
    Vector3 end = plane.position - (right * (plane.extents.x / 2));

    return _WallSegment(
      id: plane.id,
      start: start,
      end: end,
      center: plane.position,
      width: plane.extents.x,
    );
  }

  Vector3? _findIntersection(_WallSegment w1, _WallSegment w2) {
    double x1 = w1.start.x;
    double y1 = w1.start.z; // XZ plane
    double x2 = w1.end.x;
    double y2 = w1.end.z;

    double x3 = w2.start.x;
    double y3 = w2.start.z;
    double x4 = w2.end.x;
    double y4 = w2.end.z;

    double denom = (y4 - y3) * (x2 - x1) - (x4 - x3) * (y2 - y1);
    if (denom == 0) return null;

    double ua = ((x4 - x3) * (y1 - y3) - (y4 - y3) * (x1 - x3)) / denom;

    double intersectionX = x1 + ua * (x2 - x1);
    double intersectionZ = y1 + ua * (y2 - y1);

    Vector3 intersect = Vector3(intersectionX, w1.center.y, intersectionZ);

    double distToW1Start = intersect.distanceTo(w1.start);
    double distToW1End = intersect.distanceTo(w1.end);
    double distToW2Start = intersect.distanceTo(w2.start);
    double distToW2End = intersect.distanceTo(w2.end);

    double minDist1 = min(distToW1Start, distToW1End);
    double minDist2 = min(distToW2Start, distToW2End);

    // Using a loose threshold for demo purposes
    if (minDist1 < _cornerDistanceThreshold &&
        minDist2 < _cornerDistanceThreshold) {
      return intersect;
    }

    return null;
  }
}

class _WallSegment {
  String id;
  Vector3 start;
  Vector3 end;
  Vector3 center;
  double width;

  _WallSegment({
    required this.id,
    required this.start,
    required this.end,
    required this.center,
    required this.width,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'start': {'x': start.x, 'y': start.y, 'z': start.z},
    'end': {'x': end.x, 'y': end.y, 'z': end.z},
  };
}
