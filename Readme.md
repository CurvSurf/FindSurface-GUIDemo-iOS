# FindSurface-GUIDemo-iOS (Swift)

**Curv*Surf* FindSurface™** GUIDemo for iOS (Swift)

[FindSurface](https://github.com/CurvSurf/FindSurface) / [FindSurface-iOS](https://github.com/CurvSurf/FindSurface-iOS)

## Overview

This demo app demonstrates a real-time application using FindSurface to search point clouds, which ARKit provides, for geometry shapes. 


## [FindSurface Library Package](https://www.github.com/CurvSurf/FindSurface-iOS)

Unlike the older version of this demo, you don't need to download or setup the binary path for your project since the library is provided as a Swift package.


## Requirements

This demo app requires the LiDAR sensor to get a point cloud from ARKit.

- Apple iPad Pro LiDAR or newer devices with LiDAR sensor.
- Apple iPhone 12 Pro or newer devices with LiDAR sensor.
- Apple iPhone 12 Pro Max or newer devices with LiDAR sensor.

> NOTE: Based on our internal testing, we believe there are at least two practical “generations” of LiDAR depth range across iPhone models. On iPhone 11 Pro, LiDAR depth values were not produced beyond 5 m. On iPhone 16 Pro and iPhone 17 Pro, depth can be observed beyond 5 m, but it still appears to top out at roughly ~10 m.
>
>  We suspect a hardware revision introduced this step change at some point, [around iPhone 15 Pro](https://arboreal.se/en/blog/evaluation_of_lidar_sensor_iPhones_iPads?utm_source=chatgpt.com), but we have not found an official Apple source that documents the range change or a per-model maximum distance. Please treat these figures as empirical observations under our test conditions rather than guaranteed specifications.
>
>  No code changes are required. The app will automatically benefit from the extended depth range on devices that provide it. For best results, validate on the newest hardware available.

## Features

Compared to the [basic demo](https://github.com/CurvSurf/FindSurface-BasicDemo-iOS), the gui demo has the following features:

- Real-time detection of surfaces in camera scenes;
- Using input point cloud data provided by ARKit;
- Detected surfaces rendered in overlay (AR rendering);
- GUI interfaces to manipulate the app's settings (e.g., confidence, smoothed depth, feature types).


## User Interface

![interface](images/interface.png)

1. [Feature types](https://github.com/CurvSurf/FindSurface#auto-detection) of surfaces to detect.
2. Hide/show the point cloud on the screen.
3. Confidence levels to filter point cloud (e.g., the "`C.Med`" option means filter out the points having "low" confidence).
4. Point cloud scanning mode.
    - "Fixed(`Fix`)" means that FindSurface takes about 20k points from ARKit as an input for each frame.
    - "Accumulate(`Acc`)" means it takes about 500 points from ARKit as an input for each frame and accumulates them into a 500k points-sized buffer in a FIFO manner. The points are not accumulated unless the camera has a movement.
5. Switch between smoothed scene depths and scene depths (ARKit option).
6. Accuracy (error) levels of the target surface.
7. Enable/disable FindSurface to start searching geometric shapes.
8. Undo the latest snapshot.
9. Remove all snapshots.
10. Radius indicators.
    - The [seed radius](https://github.com/CurvSurf/FindSurface#how-does-it-work) indicator (the white circle), controlled by pinching the screen.
    - The picking radius indicator (the red circle), controlled by dragging the screen vertically.
    - The focusing point (the blue box) indicates the aim to the target object, to choose a [seed point](https://github.com/CurvSurf/FindSurface#how-does-it-work).
11. (A) Target surface information.
12. (B) Third-person perspective view mode (experimental, see the snapshot in the [Output Examples](#output-examples))
13. Points shown on the screen are the visualization of the points provided by ARKit, of which colors indicate confidence levels (green, blue, and red mean high, medium, and low, respectively).


## About Noise Level Estimation

`FindSurface` requires *a priori* root-mean-squared error of the measurement points (See the measurement accuracy description in [this document](https://github.com/CurvSurf/FindSurface#how-does-it-work) for details). To determine an appropriate value of the measurement accuracy parameter, we built a linear model of normal noise for the app:

````
base_error(distance) = a + b * distance * 2
// the distance is in meters.
````

We set the values of `a = 0.001` and `b = 0.00005` for the normal (expected) noise model as a result of our experiments and introduced an additional constant values for each model, of which the values have been heuristically determined, to derive the following variations of the model: 

````
lower_error(distance) = base_error(distance) - 0.001
normal_error(distance) = base_error(distance) + 0.001
higher_error(distance) = base_error(distance) + 0.003
````

The app calculates a concrete value of the *a priori* error according to the distance and the error level that users set (e.i., `E.Low`, `E.Med`, and `E.High`).



## Output Examples

**A sphere is detected**

![fixed](images/fixed-original.png)



**Points are hidden**

![hidden](images/hidden-original.png)



**Accumulated points**

![accumulated](images/accumulated-original.png)



**Third-person perspective view**

![third-person](images/third-person.PNG)