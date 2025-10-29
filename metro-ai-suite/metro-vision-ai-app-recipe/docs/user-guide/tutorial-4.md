# AI Crowd Analytics Tutorial

<!--
**Sample Description**: This tutorial demonstrates how to build an intelligent crowd analytics system using edge AI technologies for real-time vehicle detection and crowd identification in parking lots.
-->

This tutorial walks you through creating an AI-powered crowd analytics system that automatically detects vehicles and identifies whether they form a "crowd" (closely grouped vehicles) or are scattered individually. The system leverages Intel's DLStreamer framework with pre-trained AI models to process video streams and analyze vehicle clustering patterns in real-time.

<!--
**What You Can Do**: This guide covers the complete development workflow for building an AI crowd analytics application.
-->

By following this guide, you will learn how to:
- **Set up the Crowd Analytics Application**: Create a new application based on the Smart Parking template and configure it for crowd detection use cases
- **Download and Configure AI Models**: Install YOLO object detection models and custom vehicle classification models
- **Configure Video Processing Pipeline**: Set up the DLStreamer pipeline for real-time vehicle detection and crowd analysis
- **Deploy and Run the System**: Launch the containerized application and monitor crowd detection performance

## Prerequisites

- Verify that your system meets the [minimum system requirements](./system-requirements.md) for running edge AI applications
- Install Docker: [Docker Installation Guide](https://docs.docker.com/get-docker/)
- Enable running Docker without "sudo": [Post-installation steps for Linux](https://docs.docker.com/engine/install/linux-postinstall/)
- Ensure you have at least 8GB of available disk space for AI models and video files
- Basic understanding of containerized applications and video processing concepts

## Application Architecture Overview

<!--
**Architecture Image Placeholder**: Add architecture diagram showing the flow from video input through AI models to toll processing output
-->
![Crowd Analytics System Diagram](_images/ai-tolling-system.svg)


The AI Crowd Analytics system consists of several key components:
- **Video Input**: Processes live camera feeds or video files from parking lot cameras
- **Vehicle Detection**: Uses YOLOv10s model to detect and track vehicles in the parking lot
- **Vehicle Tracking**: Maintains consistent vehicle identification across video frames
- **Crowd Detection Algorithm**: Analyzes vehicle positions using Euclidean distance calculations in Node-RED to identify clusters
- **Data Processing**: Determines whether detected vehicles form a "crowd" (closely grouped) or are scattered individually
- **Real-time Analytics**: Provides live updates on crowd formation and dispersal patterns

## Set up and First Use

### 1. **Create the Crowd Analytics Application Directory**

Navigate to the metro vision AI recipe directory and create the crowd-analytics application by copying the Smart Parking template:

```bash
cd ./edge-ai-suites/metro-ai-suite/metro-vision-ai-app-recipe
cp -r smart-parking/ crowd-analytics/
```

This creates a new `crowd-analytics` directory with all the necessary application structure and configuration files.

### 2. **Download Sample Video File**

Download a sample video file containing vehicle traffic for testing the AI tolling system:

```bash
mkdir -p ./crowd-analytics/src/dlstreamer-pipeline-server/videos/
wget -O ./crowd-analytics/src/dlstreamer-pipeline-server/videos/easy1.mp4 \
  https://github.com/freedomwebtech/yolov8-advance-parkingspace-detection/raw/main/easy1.mp4

```

<details>
<summary>
Video File Details
</summary>

The sample video contains:
- Multiple vehicles in various parking scenarios
- Examples of both clustered (crowded) and scattered vehicle arrangements
- Duration: Approximately 21 seconds of footage

</details>

### 3. **Download and Setup AI Models**

Create and run the model download script to install all required AI models:

```bash
docker run --rm --user=root \
  -e http_proxy -e https_proxy -e no_proxy \
  -v "$PWD:/home/dlstreamer/metro-suite" \
  intel/dlstreamer:2025.1.2-ubuntu24 bash -c "$(cat <<EOF

cd /home/dlstreamer/metro-suite/

mkdir -p crowd-analytics/src/dlstreamer-pipeline-server/models/public
export MODELS_PATH=/home/dlstreamer/metro-suite/crowd-analytics/src/dlstreamer-pipeline-server/models
/home/dlstreamer/dlstreamer/samples/download_public_models.sh yolo11s coco128

# mkdir -p crowd-analytics/src/dlstreamer-pipeline-server/models/intel

echo "Fix ownership..."
chown -R "$(id -u):$(id -g)" crowd-analytics/src/dlstreamer-pipeline-server/models crowd-analytics/src/dlstreamer-pipeline-server/videos 2>/dev/null || true
EOF
)"
```

The installation script downloads and sets up essential AI models:

| **Model Name** | **Purpose** | **Framework** | **Size** |
|----------------|-------------|---------------|----------|
| YOLO11s | Vehicle detection and localization | PyTorch/OpenVINO | ~20MB |

<details>
<summary>
Model Download Process Details
</summary>

The installation script performs the following operations:
1. Creates the required directory structure under `src/dlstreamer-pipeline-server/models/`
2. Runs a DLStreamer container to access model download tools
3. Downloads public YOLO models using the built-in download scripts
4. Sets up proper file permissions for container access

Expected download time: 5-10 minutes depending on internet connection.

</details>

### 4. **Configure the AI Processing Pipeline**

Update the pipeline configuration to use the crowd analytics AI models. Create or update the configuration file:

```bash
cat > ./crowd-analytics/src/dlstreamer-pipeline-server/config.json << 'EOF'
{
    "config": {
        "pipelines": [
            {
                "name": "yolov11s_crowd_analytics",
                "source": "gstreamer",
                "queue_maxsize": 50,
                "pipeline": "{auto_source} name=source ! decodebin ! gvadetect model=/home/pipeline-server/models/public/yolo11s/FP32/yolo11s.xml device=CPU pre-process-backend=opencv name=detection ! queue ! gvatrack tracking-type=short-term-imageless ! queue ! gvametaconvert add-empty-results=true name=metaconvert ! queue ! gvafpscounter ! appsink name=destination",
                "description": "Vehicle detection and tracking for crowd analytics",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "detection-properties": {
                            "element": {
                                "name": "detection",
                                "format": "element-properties"
                            }
                        }
                    }
                },
                "auto_start": false
            }
        ]
    }
}
EOF
```
<details>
<summary>
Pipeline Configuration Explanation
</summary>

The GStreamer pipeline configuration defines the crowd analytics AI processing workflow:

- **Source**: Accepts video input from parking lot camera feeds or video files
- **Decode**: Converts video format to raw frames for processing  
- **gvadetect**: Runs the YOLO11s object detection model (INT8 optimized) on CPU to identify and locate vehicles in each frame
- **gvatrack**: Tracks detected vehicles across frames using imageless tracking, assigning persistent IDs to each vehicle without storing frame images
- **gvametaconvert**: Converts inference results to structured metadata with vehicle positions
- **gvafpscounter**: Monitors processing performance

</details>

### 5. **Configure Application Environment**

Update the environment configuration to use the Crowd Analytics application and create self-signed certificates for nginx:

```bash
# Update the .env file to specify the crowd-analytics application and HOST IP Address
sed -i 's/^SAMPLE_APP=.*/SAMPLE_APP=crowd-analytics/' .env
sed -i "s/^HOST_IP=.*/HOST_IP=$(hostname -I | cut -f1 -d' ')/" .env


# Create self signed certificate for nginx
mkdir -p src/nginx/ssl
cd crowd-analytics/src/nginx/ssl
if [ ! -f server.key ] || [ ! -f server.crt ]; then
    echo "Generate self-signed certificate..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout server.key -out server.crt -subj "/C=US/ST=CA/L=San Francisco/O=Intel/OU=Edge AI/CN=localhost"
    chown -R "$(id -u):$(id -g)" server.key server.crt 2>/dev/null || true

fi

# Verify the configuration
grep SAMPLE_APP= .env
grep HOST_IP= .env
```

Expected output: `SAMPLE_APP=crowd-analytics`

### 6. **Deploy the Application**

Set up the Docker Compose configuration and start the application:

```bash
# Copy the compose file for deployment
cp compose-without-scenescape.yml docker-compose.yml

# Start all services in detached mode
docker compose up -d
```

The deployment process will:
- Pull required container images
- Start the DLStreamer pipeline server
- Initialize the Node-RED flow management
- Launch the Grafana dashboard
- Set up the MQTT message broker

## Validation and Expected Results

### 1. **Verify Service Status**

Check that all services are running correctly:

```bash
docker ps
```

Expected output should show containers for:
- `dlstreamer-pipeline-server`
- `node-red`
- `grafana`
- `mosquitto` (MQTT broker)
- `nginx` (reverse proxy)
### 2. **Access the Application Interface**

Open your web browser and navigate to:
- **Main Dashboard**: `https://localhost/grafana` (Grafana)
    - Username: admin
    - Password: admin
- **Node-RED Flow Editor**: `https://localhost/nodered/`

### 3. **Test Video Processing**

Start the AI pipeline and process the sample video:

```bash
# Start the crowd analytics pipeline with the sample video
curl -k -s https://localhost/api/pipelines/user_defined_pipelines/yolov11s_crowd_analytics -X POST -H 'Content-Type: application/json' -d '
{
    "source": {
        "uri": "file:///home/pipeline-server/videos/easy1.mp4",
        "type": "uri"
    },
    "destination": {
        "metadata": {
            "type": "mqtt",
            "topic": "object_detection_1",
            "timeout": 1000
        },
        "frame": {
            "type": "webrtc",
            "peer-id": "object_detection_1"
        }
    },
    "parameters": {
        "detection-device": "CPU"
    }
}'
```

### 4. **View Live Video Stream**

Access the processed video stream with AI annotations through WebRTC:

```bash
# Open in your web browser (replace <HOST_IP> with your actual IP address)
# For local testing, typically use localhost or 127.0.0.1
http://localhost/mediamtx/object_detection_1/
```

For local testing, you can use: `http://localhost/mediamtx/object_detection_1/`

![Crowd Analytics Live Detection](_images/crowd_analytics_detection.jpg)

Expected results:
- Vehicle detection accuracy > 90% in parking lot scenarios
- Real-time vehicle tracking with consistent IDs across frames
- Crowd detection analysis showing grouped vs scattered vehicles
- Live video stream with bounding boxes and crowd indicators
- Processing at 15-30 FPS depending on hardware capabilities

## Troubleshooting

### 1. **Container Startup Issues**

If containers fail to start:
```bash
# Check container logs for specific errors
docker logs <container_name>

# Common issues:
# - Port conflicts: Ensure ports 3000, 1880, 8080 are available
# - Permission issues: Verify Docker permissions
# - Resource constraints: Check available memory and disk space
```

### 2. **Model Download Failures**

If model download fails during installation:
```bash
# Retry the installation with verbose output
./install.sh 2>&1 | tee install.log

# Check for network connectivity issues
curl -I https://github.com/openvinotoolkit/open_model_zoo

# Verify disk space
df -h
```

### 3. **Pipeline Processing Errors**

If video processing fails or shows poor accuracy:
```bash
# Check pipeline server logs
docker logs dlstreamer-pipeline-server

# Verify model files are properly installed
ls -la ./crowd-analytics/src/dlstreamer-pipeline-server/models/

# Test with different video source
# Replace the video file with a different sample
```

### 4. **Performance Issues**

For slow processing or high CPU usage:
- **Reduce video resolution**: Use lower resolution input videos
- **Adjust inference device**: Change from CPU to GPU if available
- **Optimize pipeline**: Reduce queue sizes or disable unnecessary features

## Supporting Resources

- [DLStreamer Documentation](https://dlstreamer.github.io/)
- [Metro AI Solutions](https://github.com/open-edge-platform/edge-ai-suites/tree/main/metro-ai-suite)

-----------------------------------------------
## Customizing Node-RED Flows for Hotspot Analytics Applications

<!--
**Sample Description**: This tutorial demonstrates how to customize Node-RED flows to process vehicle detection data and implement hotspot analytics logic, enabling real-time hotspot formation detection and proximity analysis.
-->

The following steps guides you through customizing Node-RED flows to implement hotspot analytics logic for vehicle detection data. You'll learn how to connect to MQTT data streams from the crowd analytics pipeline, calculate vehicle proximities using Euclidean distances, detect hotspot formations (clusters of vehicles in close proximity), and create enhanced analytics outputs.

<!--
**What You Can Do**: This guide covers the complete workflow for implementing hotspot detection algorithms in Node-RED.
-->

By following this guide, you will learn how to:
- **Access and Launch Node-RED**: Connect to the Node-RED interface and understand the flow-based programming environment
- **Clear and Reset Flows**: Remove existing flows and start with a clean workspace for custom development
- **Connect to MQTT Data Streams**: Establish connections to receive real-time AI inference data from metro vision applications
- **Implement Custom Data Processing**: Add custom names, metadata, and business logic to AI inference results using function nodes
- **Publish Enhanced Data**: Send processed data back to MQTT topics for consumption by other applications

## Prerequisites

- Complete the previous steps mentioned above to have a running crowd analytics application
- Verify that your crowd analytics application is running and producing MQTT vehicle detection data
- Basic understanding of Node-RED flow-based programming concepts
- Familiarity with MQTT messaging protocol and JSON data structures
- Web browser access to the Node-RED interface

## Hotspot Analytics Flow Architecture Overview

The custom Node-RED flow implements hotspot detection algorithms:
- **MQTT Input Node**: Subscribes to vehicle detection data from YOLO11s pipeline
- **Vehicle Position Extractor**: Parses bounding box coordinates (x, y, w, h format) to calculate centroids
- **Distance Calculator**: Computes Euclidean distances between all vehicle pairs
- **Hotspot Detector**: Applies proximity thresholds to identify hotspot formations (2+ vehicles in close proximity)
- **Analytics Generator**: Creates hotspot metrics, density maps, hotspot length measurements, and alerts
- **MQTT Output Node**: Publishes hotspot analytics data to visualization systems

## Set up and First Use

### 1. **Access the Node-RED Interface**

Launch Node-RED in your web browser using your host system's IP address:

```bash
# Find your host IP address if needed
hostname -I | awk '{print $1}'
```

Open your web browser and navigate to the Node-RED interface:
```
https://<HOST_IP>/nodered/
```
Replace `<HOST_IP>` with your actual system IP address.

<details>
<summary>
Troubleshooting Node-RED Access
</summary>

If you cannot access Node-RED:
1. Verify the crowd analytics application is running:
   ```bash
   docker ps | grep node-red
   ```
2. Check that port 1880 is exposed and accessible
3. Ensure no firewall is blocking the connection
4. Try accessing via localhost if running on the same machine: https://localhost/nodered/

</details>

### 2. **Clear Existing Node-RED Flows**

Remove any existing flows to start with a clean workspace:

1. **Select All Flows**: Press `Ctrl+A` (or `Cmd+A` on Mac) to select all nodes in the current flow
2. **Delete Selected Nodes**: Press the `Delete` key to remove all selected nodes
3. **Deploy Changes**: Click the red **Deploy** button in the top-right corner to save the changes

### 3. **Create MQTT Input Connection for Vehicle Data**

Set up an MQTT subscriber node to receive vehicle detection data:

1. **Add MQTT Input Node**:
   - Drag an `mqtt in` node from the **network** section in the left palette
   - Double-click the node to configure it

2. **Configure MQTT Broker**:
   - **Server**: `broker:1883` (or your MQTT broker address)
   - **Topic**: `object_detection_1` (crowd analytics data topic)
   - **QoS**: `0`
   - **Output**: `auto-detect (string or buffer)`

3. **Set Node Properties**:
   - **Name**: `Vehicle Detection Input`
   - Click **Done** to save the configuration

### 4. **Add Debug Output for Vehicle Data Monitoring**

Create a debug node to monitor incoming vehicle detection data:

1. **Add Debug Node**:
   - Drag a `debug` node from the **common** section
   - Connect the output of the MQTT input node to the debug node input

2. **Configure Debug Node**:
   - **Output**: `msg.payload`
   - **To**: `debug tab and console`
   - **Name**: `Vehicle Data Monitor`

3. **Deploy and Test**:
   - Click **Deploy**
   - Check the debug panel (bug icon in the right sidebar) for incoming vehicle detection messages

4. **Start the Crowd Analytics Pipeline** (if needed):
   If you don't see data in the debug panel, execute the crowd analytics pipeline using this curl command:

   ```bash
   curl -k -s https://localhost/api/pipelines/user_defined_pipelines/yolov11s_crowd_analytics -X POST -H 'Content-Type: application/json' -d '
   {
       "source": {
           "uri": "file:///home/pipeline-server/videos/easy1.mp4",
           "type": "uri"
       },
       "destination": {
           "metadata": {
               "type": "mqtt",
               "topic": "object_detection_1",
               "timeout": 1000
           },
           "frame": {
               "type": "webrtc",
               "peer-id": "object_detection_1"
           }
       },
       "parameters": {
           "detection-device": "CPU"
       }
   }'
   ```

### 5. **Implement Vehicle Position Extraction Function**

Add a function node to extract vehicle positions from detection data:

1. **Add Function Node**:
   - Drag a `function` node from the **function** section
   - Position it after the MQTT input node

2. **Configure the Vehicle Position Extractor**:
   - **Name**: `Extract Vehicle Positions`
   - **Function Code**:

```javascript
// Extract vehicle positions from YOLOv10s detection data
// Calculate centroid coordinates for each detected vehicle

// Parse JSON if payload is a string
if (typeof msg.payload === 'string') {
    try {
        msg.payload = JSON.parse(msg.payload);
    } catch (e) {
        node.warn("Failed to parse JSON: " + e.message);
        return null;
    }
}

// Check if payload exists and has metadata.objects array
if (!msg.payload || !msg.payload.metadata || !msg.payload.metadata.objects ||
    !Array.isArray(msg.payload.metadata.objects)) {
    return null; // Ignore frames without vehicle data
}

let vehicles = [];
let frameTimestamp = Date.now();
let metadata = msg.payload.metadata;

// Get frame dimensions for calculations
let frameWidth = metadata.width || 1920;
let frameHeight = metadata.height || 1080;

// Process each detected object
for (let i = 0; i < metadata.objects.length; i++) {
    let obj = metadata.objects[i];

    // Filter for cars only (you can add more vehicle types if needed)
    let vehicleTypes = ['car', 'truck', 'bus', 'motorcycle', 'vehicle'];
    if (!obj.detection || !obj.detection.label ||
        !vehicleTypes.includes(obj.detection.label.toLowerCase())) {
        continue; // Skip non-vehicle objects
    }

    // Extract bounding box coordinates (x, y, w, h format)
    let x = obj.x || 0;
    let y = obj.y || 0;
    let w = obj.w || 0;
    let h = obj.h || 0;

    if (w === 0 || h === 0) {
        continue; // Skip objects without valid dimensions
    }

    // Calculate centroid coordinates (center of bounding box)
    let centerX = x + (w / 2);
    let centerY = y + (h / 2);

    // Calculate bounding box area
    let area = w * h;

    // Get normalized coordinates from detection bounding_box
    let bbox = obj.detection.bounding_box || {};

    // Create vehicle object
    let vehicle = {
        id: obj.id || `vehicle_${i}`,
        type: obj.detection.label,
        confidence: obj.detection.confidence || 0,
        position: {
            x: centerX,      // Pixel coordinates
            y: centerY,
            x_norm: (centerX / frameWidth),     // Normalized [0-1]
            y_norm: (centerY / frameHeight)
        },
        bbox: {
            x: x,            // Top-left x in pixels
            y: y,            // Top-left y in pixels
            width: w,        // Width in pixels
            height: h,       // Height in pixels
            area: area,      // Area in square pixels
            x_min_norm: bbox.x_min || 0,        // Normalized coordinates
            y_min_norm: bbox.y_min || 0,
            x_max_norm: bbox.x_max || 0,
            y_max_norm: bbox.y_max || 0
        },
        timestamp: frameTimestamp
    };

    vehicles.push(vehicle);
}

// Only process frames with vehicles
if (vehicles.length === 0) {
    return null;
}

// Create output message with vehicle positions
msg.payload = {
    timestamp: frameTimestamp,
    frame_dimensions: {
        width: frameWidth,
        height: frameHeight
    },
    vehicle_count: vehicles.length,
    vehicles: vehicles
};

return msg;
```

### 6. **Implement Hotspot Detection Algorithm**

Add a function node to calculate inter-vehicle distances and detect hotspots:

1. **Add Function Node**:
   - Drag another `function` node from the **function** section
   - Connect it after the `Extract Vehicle Positions` node

2. **Configure the Hotspot Detection Logic**:
   - **Name**: `Hotspot Detection Algorithm`
   - **Function Code**:

```javascript
// Hotspot Detection Algorithm for PARKED Vehicles
// Tracks vehicle positions across frames to identify stationary (parked) vehicles
// Calculates hotspots only for parked vehicles

// Initialize persistent storage for tracking vehicles across frames
if (!context.vehicleHistory) {
    context.vehicleHistory = {};
}

if (!context.previousHotspots) {
    context.previousHotspots = {};  // NEW: Track previous hotspots
}

if (!msg.payload || !msg.payload.vehicles || msg.payload.vehicles.length === 0) {
    // No vehicles detected
    msg.payload = {
        ...msg.payload,
        hotspot_count: 0,
        hotspots: [],
        parked_vehicles: []
    };
    return msg;
}

let vehicles = msg.payload.vehicles;
let currentTimestamp = msg.payload.timestamp;

// Configuration parameters
const DISTANCE_THRESHOLD = 150;
const MIN_HOTSPOT_SIZE = 2;
const PARKED_THRESHOLD = 10;
const PARKED_FRAMES_REQUIRED = 60;
const MOVING_FRAMES_GRACE = 20;
const HISTORY_TIMEOUT = 5000;
const DISTANCE_MODE = "euclidean";
const INCLUDE_OVERLAPPING = true;
const OVERLAP_THRESHOLD = 0.3;
const HOTSPOT_STABILITY_FRAMES = 30;  // NEW: Hotspot must exist for 30 frames before publishing

// Function to calculate distance between two points based on selected mode
function calculateDistance(pos1, pos2, mode = DISTANCE_MODE) {
    let dx = Math.abs(pos1.x - pos2.x);
    let dy = Math.abs(pos1.y - pos2.y);
    
    switch (mode) {
        case "horizontal":
            return dx;
        case "vertical":
            return dy;
        case "manhattan":
            return dx + dy;
        case "euclidean":
        default:
            return Math.sqrt(dx * dx + dy * dy);
    }
}

// Function to calculate bounding box overlap (IoU)
function calculateBBoxOverlap(bbox1, bbox2) {
    let xLeft = Math.max(bbox1.x, bbox2.x);
    let yTop = Math.max(bbox1.y, bbox2.y);
    let xRight = Math.min(bbox1.x + bbox1.width, bbox2.x + bbox2.width);
    let yBottom = Math.min(bbox1.y + bbox1.height, bbox2.y + bbox2.height);

    if (xRight < xLeft || yBottom < yTop) {
        return 0;
    }

    let intersectionArea = (xRight - xLeft) * (yBottom - yTop);
    let union = bbox1.area + bbox2.area - intersectionArea;

    return intersectionArea / union;
}

// Clean up old vehicle history
let historyIds = Object.keys(context.vehicleHistory);
for (let id of historyIds) {
    if (currentTimestamp - context.vehicleHistory[id].lastSeen > HISTORY_TIMEOUT) {
        delete context.vehicleHistory[id];
    }
}

// Update vehicle history and determine parked status
let parkedVehicles = [];

for (let vehicle of vehicles) {
    let vehicleId = vehicle.id;

    if (!context.vehicleHistory[vehicleId]) {
        // New vehicle detected
        context.vehicleHistory[vehicleId] = {
            id: vehicleId,
            positions: [vehicle.position],
            firstSeen: currentTimestamp,
            lastSeen: currentTimestamp,
            stationaryFrames: 0,
            movingFrames: 0,
            isParked: false
        };
    } else {
        // Existing vehicle - check if it has moved
        let history = context.vehicleHistory[vehicleId];
        let lastPosition = history.positions[history.positions.length - 1];
        let movement = calculateDistance(vehicle.position, lastPosition);

        // Update position history (keep last 20 positions)
        history.positions.push(vehicle.position);
        if (history.positions.length > 20) {
            history.positions.shift();
        }

        history.lastSeen = currentTimestamp;

        // Check if vehicle is stationary WITH GRACE PERIOD
        if (movement <= PARKED_THRESHOLD) {
            history.stationaryFrames++;
            history.movingFrames = 0;
        } else {
            history.movingFrames = (history.movingFrames || 0) + 1;
            
            if (history.movingFrames >= MOVING_FRAMES_GRACE) {
                history.stationaryFrames = 0;
                history.isParked = false;
            }
        }

        if (history.stationaryFrames >= PARKED_FRAMES_REQUIRED) {
            history.isParked = true;
        }
    }

    if (context.vehicleHistory[vehicleId].isParked) {
        parkedVehicles.push({
            ...vehicle,
            parked_frames: context.vehicleHistory[vehicleId].stationaryFrames,
            parked_duration_ms: currentTimestamp - context.vehicleHistory[vehicleId].firstSeen
        });
    }
}

// Only process hotspots if we have 2+ parked vehicles
if (parkedVehicles.length < MIN_HOTSPOT_SIZE) {
    msg.payload = {
        ...msg.payload,
        total_vehicles: vehicles.length,
        parked_vehicles_count: parkedVehicles.length,
        hotspot_count: 0,
        hotspots: [],
        parked_vehicles: parkedVehicles.map(v => ({
            id: v.id,
            type: v.type,
            position: v.position,
            parked_duration_ms: v.parked_duration_ms
        }))
    };
    return msg;
}

// Calculate distance matrix between all parked vehicle pairs
let distanceMatrix = [];
let proximityPairs = [];

for (let i = 0; i < parkedVehicles.length; i++) {
    distanceMatrix[i] = [];
    for (let j = 0; j < parkedVehicles.length; j++) {
        if (i === j) {
            distanceMatrix[i][j] = 0;
        } else {
            let distance = calculateDistance(parkedVehicles[i].position, parkedVehicles[j].position);
            distanceMatrix[i][j] = distance;

            if (distance <= DISTANCE_THRESHOLD) {
                let overlap = calculateBBoxOverlap(parkedVehicles[i].bbox, parkedVehicles[j].bbox);
                let willBeInSameHotspot = INCLUDE_OVERLAPPING ? true : (overlap < OVERLAP_THRESHOLD);
                
                proximityPairs.push({
                    vehicle1_id: parkedVehicles[i].id,
                    vehicle2_id: parkedVehicles[j].id,
                    distance: Math.round(distance * 100) / 100,
                    overlap: Math.round(overlap * 1000) / 1000,
                    is_hotspot_pair: willBeInSameHotspot
                });
            }
        }
    }
}

// Cluster parked vehicles into hotspots using connected components
let visited = new Array(parkedVehicles.length).fill(false);
let hotspots = [];

function findHotspot(vehicleIndex, currentHotspot) {
    visited[vehicleIndex] = true;
    currentHotspot.push(vehicleIndex);

    for (let j = 0; j < parkedVehicles.length; j++) {
        if (!visited[j] && distanceMatrix[vehicleIndex][j] <= DISTANCE_THRESHOLD) {
            if (INCLUDE_OVERLAPPING) {
                findHotspot(j, currentHotspot);
            } else {
                let overlap = calculateBBoxOverlap(parkedVehicles[vehicleIndex].bbox, parkedVehicles[j].bbox);
                if (overlap < OVERLAP_THRESHOLD) {
                    findHotspot(j, currentHotspot);
                }
            }
        }
    }
}

// Find all hotspots
for (let i = 0; i < parkedVehicles.length; i++) {
    if (!visited[i]) {
        let hotspot = [];
        findHotspot(i, hotspot);

        if (hotspot.length >= MIN_HOTSPOT_SIZE) {
            let hotspotVehicles = hotspot.map(idx => parkedVehicles[idx]);

            // Calculate hotspot centroid
            let centroidX = hotspotVehicles.reduce((sum, v) => sum + v.position.x, 0) / hotspotVehicles.length;
            let centroidY = hotspotVehicles.reduce((sum, v) => sum + v.position.y, 0) / hotspotVehicles.length;

            // Calculate hotspot length (maximum distance between any two parked vehicles)
            let distances = [];
            for (let m = 0; m < hotspot.length; m++) {
                for (let n = m + 1; n < hotspot.length; n++) {
                    distances.push(distanceMatrix[hotspot[m]][hotspot[n]]);
                }
            }

            let avgDistance = distances.length > 0 ?
                distances.reduce((sum, d) => sum + d, 0) / distances.length : 0;
            let maxDistance = distances.length > 0 ? Math.max(...distances) : 0;

            // Calculate hotspot bounding box
            let minX = Math.min(...hotspotVehicles.map(v => v.bbox.x));
            let minY = Math.min(...hotspotVehicles.map(v => v.bbox.y));
            let maxX = Math.max(...hotspotVehicles.map(v => v.bbox.x + v.bbox.width));
            let maxY = Math.max(...hotspotVehicles.map(v => v.bbox.y + v.bbox.height));

            let hotspotWidth = maxX - minX;
            let hotspotHeight = maxY - minY;

            // Calculate hotspot density
            let hotspotArea = Math.PI * Math.pow(maxDistance / 2, 2);
            let density = hotspotVehicles.length / (hotspotArea || 1);

            // Generate persistent hotspot ID based on vehicle IDs
            let vehicleIdSet = hotspotVehicles.map(v => v.id).sort((a,b) => a-b).join('_');
            let hotspotId = "hotspot_" + vehicleIdSet;

            hotspots.push({
                id: hotspotId,
                vehicle_count: hotspotVehicles.length,
                vehicle_ids: vehicleIdSet,
                vehicles: hotspotVehicles.map(v => ({
                    id: v.id,
                    type: v.type,
                    confidence: v.confidence,
                    parked_duration_ms: v.parked_duration_ms
                })),
                centroid: {
                    x: Math.round(centroidX),
                    y: Math.round(centroidY)
                },
                avg_distance: Math.round(avgDistance * 100) / 100,
                max_distance: Math.round(maxDistance * 100) / 100,
                bounding_box: {
                    x: Math.round(minX),
                    y: Math.round(minY),
                    width: Math.round(hotspotWidth),
                    height: Math.round(hotspotHeight)
                },
                density: Math.round(density * 1000) / 1000
            });
        }
    }
}

// ==================== NEW: HOTSPOT STABILITY TRACKING ====================
let currentHotspotIds = new Set();
let stableHotspotsToPublish = [];

hotspots.forEach(hotspot => {
    let hotspotKey = hotspot.vehicle_ids;
    currentHotspotIds.add(hotspotKey);
    
    if (!context.previousHotspots[hotspotKey]) {
        // New hotspot detected
        context.previousHotspots[hotspotKey] = {
            firstSeen: currentTimestamp,
            frameCount: 1,
            published: false,
            data: hotspot
        };
    } else {
        // Existing hotspot - increment frame count
        context.previousHotspots[hotspotKey].frameCount++;
        context.previousHotspots[hotspotKey].data = hotspot;  // Update with latest data
    }
    
    // Only publish stable hotspots (existed for HOTSPOT_STABILITY_FRAMES)
    if (context.previousHotspots[hotspotKey].frameCount >= HOTSPOT_STABILITY_FRAMES) {
        stableHotspotsToPublish.push(hotspot);
        
        if (!context.previousHotspots[hotspotKey].published) {
            context.previousHotspots[hotspotKey].published = true;
            node.warn("NEW STABLE HOTSPOT: [" + hotspot.vehicle_ids.replace(/_/g, ", ") + "]");
        }
    }
});

// Clean up disappeared hotspots
for (let key in context.previousHotspots) {
    if (!currentHotspotIds.has(key)) {
        // Hotspot no longer exists
        if (context.previousHotspots[key].published) {
            node.warn("HOTSPOT ENDED: [" + key.replace(/_/g, ", ") + "]");
        }
        delete context.previousHotspots[key];
    }
}
// =========================================================================

// Create output with hotspot analytics
msg.payload = {
    ...msg.payload,
    total_vehicles: vehicles.length,
    parked_vehicles_count: parkedVehicles.length,
    hotspot_count: stableHotspotsToPublish.length,  // Only stable hotspots
    hotspots: stableHotspotsToPublish,              // Only stable hotspots
    parked_vehicles: parkedVehicles.map(v => ({
        id: v.id,
        type: v.type,
        position: v.position,
        parked_duration_ms: v.parked_duration_ms,
        parked_frames: v.parked_frames
    })),
    proximity_pairs: proximityPairs.filter(pair => pair.is_hotspot_pair),
    distance_threshold: DISTANCE_THRESHOLD,
    distance_mode: DISTANCE_MODE,
    include_overlapping: INCLUDE_OVERLAPPING,
    overlap_threshold: OVERLAP_THRESHOLD,
    parked_threshold: PARKED_THRESHOLD
};

return msg;
```


### 7. **Add Hotspot Analytics Output Processing**

Create a function node to generate hotspot analytics summaries and alerts:

1. **Add Function Node**:
   - Drag another `function` node from the **function** section
   - Connect it after the `Hotspot Detection Algorithm` node

2. **Configure Analytics Generator**:
   - **Name**: `Generate Hotspot Analytics`
   - **Function Code**:

```javascript
// Generate Hotspot Analytics for PARKED Vehicles
// Output: Simple table-friendly format for Grafana

if (!msg.payload || !msg.payload.hotspots) {
    return null;
}

let hotspots = msg.payload.hotspots || [];
let timestamp = msg.payload.timestamp;

// Create table-friendly output with one row per hotspot
let tableData = hotspots.map((hotspot, index) => {
    // Calculate average parked duration and frames for vehicles in this hotspot
    let totalDuration = 0;
    let totalFrames = 0;
    let vehicleIds = [];

    // hotspot.vehicles is an array of vehicle objects with parked_duration_ms
    for (let vehicle of hotspot.vehicles) {
        vehicleIds.push(vehicle.id);
        totalDuration += vehicle.parked_duration_ms || 0;

        // Calculate frames from duration if not available (assuming 30fps)
        let frames = vehicle.parked_frames || Math.round((vehicle.parked_duration_ms || 0) / 33.33);
        totalFrames += frames;
    }

    let vehicleCount = hotspot.vehicles.length;
    let avgDurationSec = vehicleCount > 0 ? Math.round(totalDuration / vehicleCount / 1000) : 0;
    let avgFrames = vehicleCount > 0 ? Math.round(totalFrames / vehicleCount) : 0;

    return {
        timestamp: timestamp,
        hotspot_id: hotspot.id,
        hotspot_number: index + 1,
        vehicle_count: hotspot.vehicle_count,
        centroid_x: Math.round(hotspot.centroid.x),
        centroid_y: Math.round(hotspot.centroid.y),
        avg_distance_px: Math.round(hotspot.avg_distance),
        max_distance_px: Math.round(hotspot.max_distance),
        vehicle_ids: vehicleIds.join(', '),
        avg_parked_duration_sec: avgDurationSec,
        avg_parked_frames: avgFrames
    };
});

// If no hotspots, don't send anything
if (tableData.length === 0) {
    return null;
}

// Split array into individual messages (one per hotspot)
// Each hotspot becomes a separate MQTT message for proper Grafana table visualization
return tableData.map(hotspot => {
    return { payload: hotspot };
});
```

### 8. **Configure MQTT Output for Hotspot Analytics**

Set up a single MQTT publisher for hotspot analytics data:

1. **Add MQTT Output Node**:
   - Drag an `mqtt out` node from the **network** section
   - Connect the output of the analytics generator to this node
   - **Configure**:
     - **Server**: Same as input (`broker:1883`)
     - **Topic**: `hotspot_analytics` (or use `msg.topic` for dynamic topics)
     - **QoS**: `0`
     - **Retain**: `false`
     - **Name**: `Hotspot Analytics Publisher`

### 9. **Add Debug Monitoring**

Create debug nodes to monitor the hotspot analytics pipeline:

1. **Add Debug Nodes**:
   - Add debug nodes after each function node
   - **Names**: 
     - `Vehicle Positions Debug`
     - `Hotspot Detection Debug`
     - `Analytics Output Debug`

2. **Configure Debug Outputs**:
   - Set each debug node to output `msg.payload`
   - Enable console output for troubleshooting

### 10. **Deploy and Validate the Crowd Analytics Flow**

Test your complete crowd analytics Node-RED flow:

1. **Deploy the Complete Flow**:
   - Click the Deploy button on the Top Right side in Node-RED interface

2. **Monitor Crowd Analytics**:
   - Open the debug panel in Node-RED
   - Start the crowd analytics pipeline using the curl command from step 4
   - Verify that vehicle detection data flows through each stage
   - Check that hotspot detection algorithms are working correctly
   - Monitor hotspot analytics outputs in real-time

3. **Validate Hotspot Detection Logic**:
   - Test with different video sources containing various vehicle densities
   - Verify distance calculations are accurate
   - Check that hotspots are properly identified
   - Validate alert generation for different congestion scenarios
   - Review hotspot length calculations in the output

## Expected Results

![Hotspot Analytics Node-RED Flow](_images/crowd-analytics-node-red-flow.png)

After completing this tutorial, you should have:

1. **Complete Hotspot Analytics Flow**: A working Node-RED flow that tracks parked vehicles and detects hotspot formations
2. **Parked Vehicle Detection**: Automatic identification of stationary (parked) vehicles by tracking position across frames
3. **Real-time Hotspot Detection**: Live identification of parking hotspots (2+ parked vehicles within 150 pixels)
4. **Single MQTT Topic**: Clean, table-ready data published to `hotspot_analytics` for easy Grafana visualization
5. **Enhanced Analytics**: Per-hotspot metrics including:
   - Vehicle count per hotspot
   - Location coordinates (centroid)
   - Distance metrics between parked vehicles
   - Vehicle tracking IDs
   - Overall summary statistics (total vehicles, parked count, hotspot count)


## Troubleshooting

### **Node-RED Interface Not Accessible**
- **Problem**: Cannot access Node-RED at the specified URL
- **Solution**: 
  ```bash
  # Check if Node-RED container is running
  docker ps | grep node-red
  # Restart the metro vision AI application if needed
  ./sample_stop.sh && ./sample_start.sh
  ```

### **No Data in Debug Panel**
- **Problem**: Debug nodes show no incoming data
- **Solution**: 
  - Verify the AI application is running and generating inference data
  - Check MQTT topic names match your application's output topics
  - Ensure proper JSON parsing in function nodes

### **Function Node Errors**
- **Problem**: Function node shows errors in the debug panel
- **Solution**: 
  - Add try-catch blocks around JSON parsing
  - Use `node.warn()` or `node.error()` for debugging
  - Validate input data structure before processing

## Supporting Resources

- [Node-RED Official Documentation](https://nodered.org/docs/)
- [MQTT Protocol Specification](https://mqtt.org/)
- [Intel DLStreamer Documentation](https://dlstreamer.github.io/)
- [Metro AI Solutions](https://github.com/open-edge-platform/edge-ai-suites/tree/main/metro-ai-suite)
-----------------------------

After successfully implementing hotspot analytics with Node-RED, follow the follwing steps to set up Grafana dashboards for visualizing the hotspot data and metrics. This will allow you to monitor vehicle congestion and hotspot formations in real-time, providing valuable insights for traffic management and urban planning.

### Visualizing Hotspot Analytics in Grafana

The hotspot analytics data published to `hotspot_analytics` can be visualized in real-time using Grafana.

#### **Quick Setup Steps**

1. **Access Grafana**: Navigate to `https://localhost/grafana` (Username: `admin`, Password: `admin`)

2. **Create New Dashboard**:
   - Click "+" → "New Dashboard" → "Add Visualization"
   - Select **Table** visualization type
   - Set Data Source to **grafana-mqtt-datasource**
   - Set Topic to **hotspot_analytics**

3. **Add Transformations** (Transform tab at bottom):
   
   **What you'll see initially**: Two columns - "Time" and "Value" (Value contains the JSON array as text)
   
   a. **Extract fields** :
      - Click **"+ Add transformation"** → Select **"Extract fields"**
      - **Source**: Select **"Value"** (with capital V - this column contains the JSON array)
      - **Format**: Select **"Auto"** (automatically detects and parses JSON array)
      - **Replace all fields**: ✅ **Check this box** (replaces Time/Value with expanded fields)
      - Click **Apply**
      
      **Result**: The JSON array will expand into individual columns (hotspot_number, vehicle_count, etc.)
   
   b. **Sort by** (CRITICAL - orders data by time for deduplication):
      - Click **"+ Add transformation"** → Select **"Sort by"**
      - **Field**: Select **"Time"**
      - **Order**: Select **Descending** (newest first)
      - Click **Apply**
      
      **Purpose**: Ensures the most recent data for each hotspot appears first
   
   c. **Group by** (CRITICAL - removes duplicate hotspots):
      - Click **"+ Add transformation"** → Select **"Group by"**
      - **Group by**: Select **"hotspot_id"**
      - **Calculations** (configure for each field):
        - `timestamp`: Select **"Last"**
        - `hotspot_number`: Select **"Last"**
        - `vehicle_count`: Select **"Last"**
        - `centroid_x`: Select **"Last"**
        - `centroid_y`: Select **"Last"**
        - `avg_distance_px`: Select **"Last"**
        - `max_distance_px`: Select **"Last"**
        - `vehicle_ids`: Select **"Last"**
        - `avg_parked_duration_sec`: Select **"Last"**
        - `avg_parked_frames`: Select **"Last"**
      - Click **Apply**
      
      **Result**: Each unique hotspot_id appears only once with its most recent data
   
   d. **Organize fields** (Optional - for better column names):
      - Click **"+ Add transformation"** → Select **"Organize fields by name"**
      - Rename fields for display:
        - `hotspot_number` → "Hotspot #"
        - `vehicle_count` → "Vehicles"
        - `centroid_x` → "Location X"
        - `centroid_y` → "Location Y"
        - `avg_distance_px` → "Avg Distance (px)"
        - `max_distance_px` → "Max Distance (px)"
        - `vehicle_ids` → "Vehicle IDs"
        - `avg_parked_duration_sec` → "Parked Duration (s)"
        - `avg_parked_frames` → "Parked Frames"
      - Hide unwanted fields (timestamp, hotspot_id) by clicking the eye icon

4. **Configure Time Window and Refresh** (for real-time display):
   - **Time Range** (top-right corner): Set to **"Last 10 seconds"**
   - **Auto-refresh**: Select **"5s"** from dropdown
   - **Query Options** (in Query tab):
     - Leave **"Max data points"** empty or set to **0** (unlimited)
     - ⚠️ **Important**: Do NOT set "Max data points" to a small number (e.g., 3) as this limits MQTT messages, not unique hotspots, causing duplicate rows
   - **Panel Title**: "Parking Hotspot Analytics"
   - Click **Save**

**Troubleshooting**:
- **No data appearing**: Verify Node-RED flow is deployed and pipeline is running
- **Only seeing "Time" and "Value" columns**: You need to add the **Extract fields** transformation (Source: "Value", Format: "Auto")
- **Value column shows JSON text**: This is correct - add Extract fields transformation to parse it
- **Columns still not expanding**: Make sure "Replace all fields" is checked in Extract fields transformation
- **Array showing as text in one cell**: The Extract fields transformation will fix this - select Source as "Value" and Format as "Auto"
- **Same hotspot appearing multiple times**: Add the **"Sort by"** and **"Group by hotspot_id"** transformations to deduplicate
- **Set "Max data points" to 3 but seeing duplicates**: Remove "Max data points" setting - it limits MQTT messages (not unique hotspots), use "Group by" transformation instead
- **Multiple hotspots not showing when expected**: Check time window is at least 10 seconds and "Max data points" is not set to a low number
- **Only 1 row shown when 3 hotspots exist**: Verify all transformations are applied in correct order: Extract fields → Sort by → Group by


## Troubleshooting

### **No Vehicle Detection Data**
- **Problem**: Debug nodes show no incoming vehicle data
- **Solution**: 
  ```bash
  # Verify crowd analytics pipeline is running
  curl -k -s https://localhost/api/pipelines/user_defined_pipelines/yolov11s_crowd_analytics
  # Check MQTT broker connectivity
  docker logs <mqtt-container-name>
  ```

### **Incorrect Distance Calculations**
- **Problem**: Hotspot detection not working properly
- **Solution**: 
  - Verify bounding box coordinates are valid (x, y, w, h format)
  - Check centroid calculations in vehicle position extractor
  - Adjust `DISTANCE_THRESHOLD` for your specific video resolution (default: 150 pixels for 1920x1080)

### **No Hotspots Detected**
- **Problem**: Vehicles are present but no hotspots detected
- **Solution**: 
  - Increase the `DISTANCE_THRESHOLD` value (try 200-300 pixels)
  - Verify `MIN_HOTSPOT_SIZE` is set to 2 vehicles
  - Check vehicle filtering logic (car, truck, bus types)
  - Review proximity_pairs in debug output to see actual distances

### **Function Node Errors**
- **Problem**: JavaScript errors in hotspot detection functions
- **Solution**: 
  - Add error handling with try-catch blocks
  - Use `node.warn()` for debugging intermediate values
  - Validate input data structure before processing
  - Check that msg.payload.metadata.objects exists

### **Hotspot Length Not Calculated**
- **Problem**: Hotspot length shows as 0 or undefined
- **Solution**:
  - Verify that multiple vehicles are detected in the hotspot
  - Check that Euclidean distance calculations are working
  - Review the `max_distance` field in hotspot output
  - Ensure distanceMatrix is populated correctly

## Supporting Resources

- [Node-RED Official Documentation](https://nodered.org/docs/)
- [Euclidean Distance Algorithms](https://en.wikipedia.org/wiki/Euclidean_distance)
- [Crowd Dynamics Theory](https://en.wikipedia.org/wiki/Crowd_dynamics)
- [Intel DLStreamer Documentation](https://dlstreamer.github.io/)
- [Metro AI Solutions](https://github.com/open-edge-platform/edge-ai-suites/tree/main/metro-ai-suite)