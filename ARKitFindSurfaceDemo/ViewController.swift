//
//  ViewController.swift
//  ARKitFindSurfaceDemo
//
//  Main view controller for the AR experience.
//

import UIKit
import Metal
import MetalKit
import ARKit
import FindSurfaceFramework

let MIN_TOUCH_RADIUS_PIXEL: Float = 32.0
let MIN_PROBE_RADIUS_PIXEL: Float = 2.5

extension MTKView : RenderDestinationProvider {
}

class ViewController: UIViewController, MTKViewDelegate, ARSessionDelegate {
    
    private let confidenceControl = UISegmentedControl(items: ["Low", "Medium", "High"])
    private let smoothedControl   = UISegmentedControl(items: ["Smoothed", "Normal"])
    private let sampleControl     = UISegmentedControl(items: ["Fixed", "Accumulate"])
    private let typeControl       = UISegmentedControl(items: [UIImage(named: "icon_any")!,
                                                               UIImage(named: "icon_plane")!,
                                                               UIImage(named: "icon_sphere")!,
                                                               UIImage(named: "icon_cylinder")!,
                                                               UIImage(named: "icon_cone")!,
                                                               UIImage(named: "icon_torus")!])
    private let gazePointView     = UIImageView(image: UIImage(named: "cube"))
    private let touchRadiusView   = UIView()
    private let probeRadiusView   = UIView()
    
    private let findButton        = UIButton()
    private let captureButton     = UIButton()
    private let deleteButton      = UIButton()
    private let undoButton        = UIButton()
    private let showHideButton    = UIButton()
    
    var session: ARSession!
    var renderer: Renderer!
    
    var fsCtx: FindSurface!
    var findType: FindSurface.FeatureType = .sphere
    var touchRadiusPixel: Float = 64.0  // Touch Radius Indicator View Radius in Pixel
    var probeRadiusPixel: Float = 10.0  // Probe Radius Indicator View Radius in Pixel
    var isFindSurfaceBusy: Bool = false
    var fsTaskQueue = DispatchQueue(label:"FindSurfaceQueue", attributes: [], autoreleaseFrequency: .workItem)
    
    // Calculated Property
    var MAX_VIEW_RADIUS: Float { get { return min( Float(self.view.bounds.width), Float(self.view.bounds.height) ) / 2.0 } }
    
    // LayoutConstraint
    var touchRadiusWidthConstraint: NSLayoutConstraint? = nil
    var touchRadiusHeightConstraint: NSLayoutConstraint? = nil
    var probeRadiusWidthConstraint: NSLayoutConstraint? = nil
    var probeRadiusHeightConstraint: NSLayoutConstraint? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Get FindSurface Instance
        fsCtx = FindSurface.sharedInstance()
        fsCtx.smartConversionOptions = [.cone2Cylinder, .torus2Cylinder, .torus2Sphere]
        
        // Set the view's delegate
        session = ARSession()
        session.delegate = self
        
        // Set the view to use the default device
        if let view = self.view as? MTKView {
            view.device = MTLCreateSystemDefaultDevice()
            view.backgroundColor = UIColor.clear
            view.delegate = self
            
            guard view.device != nil else {
                print("Metal is not supported on this device")
                return
            }
            
            // Configure the renderer to draw to the view
            renderer = Renderer(session: session, metalDevice: view.device!, renderDestination: view)
            
            renderer.drawRectResized(size: view.bounds.size)
        }
        
        // Confidence control
        confidenceControl.backgroundColor = .white
        confidenceControl.selectedSegmentIndex = renderer.confidenceThreshold
        confidenceControl.addTarget(self, action: #selector(viewValueChanged), for: .valueChanged)
        
        // SmoothedSceneDepth control
        smoothedControl.backgroundColor = .white
        smoothedControl.selectedSegmentIndex = renderer.useSmoothedSceneDepth ? 0 : 1
        smoothedControl.addTarget(self, action: #selector(viewValueChanged), for: .valueChanged)
        
        // Point Cloud sampling control
        sampleControl.backgroundColor = .white
        sampleControl.selectedSegmentIndex = renderer.useFullSampling ? 0 : 1
        sampleControl.addTarget(self, action: #selector(viewValueChanged), for: .valueChanged)
        
        // FindType control
        typeControl.selectedSegmentIndex = Int(findType.rawValue)
        typeControl.addTarget(self, action: #selector(viewValueChanged), for: .valueChanged)
        typeControl.translatesAutoresizingMaskIntoConstraints = false
        
        // Put 3 controls to StackView
        let stackView = UIStackView(arrangedSubviews: [ confidenceControl, sampleControl, smoothedControl ])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 20
        
        // Gaze Point View
        gazePointView.isOpaque = true
        gazePointView.alpha    = 0.5
        gazePointView.translatesAutoresizingMaskIntoConstraints = false
        
        // TouchRadius Indicator View
        let _diameter = CGFloat(2.0 * touchRadiusPixel)
        touchRadiusView.translatesAutoresizingMaskIntoConstraints = false
        touchRadiusView.layer.borderWidth = CGFloat(2.0)
        touchRadiusView.layer.borderColor = UIColor.white.cgColor
        touchRadiusView.layer.cornerRadius = CGFloat(touchRadiusPixel)
        //touchRadiusView.frame.size = CGSize(width: _diameter, height: _diameter)
        
        // ProbeRadius Indicator View
        let _diameter2 = CGFloat(2.0 * probeRadiusPixel)
        probeRadiusView.translatesAutoresizingMaskIntoConstraints = false
        probeRadiusView.layer.borderWidth = CGFloat(2.0)
        probeRadiusView.layer.borderColor = UIColor.red.cgColor
        probeRadiusView.layer.cornerRadius = CGFloat(probeRadiusPixel)
        
        // Find Button
        findButton.setImage(UIImage(named: "findBtn"), for: .normal)
        findButton.setImage(UIImage(named: "stop"), for: .selected)
        findButton.addTarget(self, action: #selector(onClickButton), for: .touchUpInside)
        findButton.translatesAutoresizingMaskIntoConstraints = false
        
        // Capture Button
        captureButton.setImage(UIImage(named: "capture"), for: .normal)
        captureButton.addTarget(self, action: #selector(onClickButton), for: .touchUpInside)
        captureButton.isHidden = true
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        
        // Delete Button
        deleteButton.setImage(UIImage(named: "delete"), for: .normal)
        deleteButton.addTarget(self, action: #selector(onClickButton), for: .touchUpInside)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        
        // Back(Undo) Button
        undoButton.setImage(UIImage(named: "back"), for: .normal)
        undoButton.addTarget(self, action: #selector(onClickButton), for: .touchUpInside)
        undoButton.translatesAutoresizingMaskIntoConstraints = false
        
        // Show/Hide (PointCloud) Button
        let showHideConfig = UIImage.SymbolConfiguration(scale: .large)
        showHideButton.setImage(UIImage(systemName: "eye"), for: .normal)
        showHideButton.setPreferredSymbolConfiguration(showHideConfig, forImageIn: .normal)
        showHideButton.setImage(UIImage(systemName: "eye.slash"), for: .selected)
        showHideButton.setPreferredSymbolConfiguration(showHideConfig, forImageIn: .selected)
        showHideButton.tintColor = UIColor.white
        showHideButton.addTarget(self, action: #selector(onClickButton), for: .touchUpInside)
        showHideButton.backgroundColor = UIColor.init(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.3)
        showHideButton.translatesAutoresizingMaskIntoConstraints = false
        showHideButton.layer.cornerRadius = CGFloat(24)
        
        // Add View
        view.addSubview(gazePointView)
        view.addSubview(touchRadiusView)
        view.addSubview(probeRadiusView)
        view.addSubview(stackView)
        view.addSubview(typeControl)
        view.addSubview(findButton)
        view.addSubview(captureButton)
        view.addSubview(deleteButton)
        view.addSubview(undoButton)
        view.addSubview(showHideButton)
        
        touchRadiusWidthConstraint  = touchRadiusView.widthAnchor.constraint(equalToConstant: _diameter)
        touchRadiusHeightConstraint = touchRadiusView.heightAnchor.constraint(equalToConstant: _diameter)
        probeRadiusWidthConstraint  = probeRadiusView.widthAnchor.constraint(equalToConstant: _diameter2)
        probeRadiusHeightConstraint = probeRadiusView.heightAnchor.constraint(equalToConstant: _diameter2)
        
        // Set Layout
        NSLayoutConstraint.activate([
            // StackView
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -32),
            // FindType Control
            typeControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            typeControl.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            typeControl.heightAnchor.constraint(equalToConstant: 40.0),
            // Gaze Point View
            gazePointView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            gazePointView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            // Touch Radius Indicator View
            touchRadiusView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            touchRadiusView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            touchRadiusWidthConstraint!,
            touchRadiusHeightConstraint!,
            // Probe Radius Indicator View
            probeRadiusView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            probeRadiusView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            probeRadiusWidthConstraint!,
            probeRadiusHeightConstraint!,
            // FindButton
            findButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            findButton.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -16),
            findButton.widthAnchor.constraint(equalToConstant: CGFloat(64)),
            findButton.heightAnchor.constraint(equalToConstant: CGFloat(64)),
            // Capture Button
            captureButton.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -16),
            captureButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            captureButton.widthAnchor.constraint(equalToConstant: CGFloat(48)),
            captureButton.heightAnchor.constraint(equalToConstant: CGFloat(48)),
            // DeleteButton
            deleteButton.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -16),
            deleteButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            deleteButton.widthAnchor.constraint(equalToConstant: CGFloat(48)),
            deleteButton.heightAnchor.constraint(equalToConstant: CGFloat(48)),
            // Back(Undo)Button
            undoButton.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 16),
            undoButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            undoButton.widthAnchor.constraint(equalToConstant: CGFloat(48)),
            undoButton.heightAnchor.constraint(equalToConstant: CGFloat(48)),
            // Show/Hide (PointCloud) Button
            showHideButton.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 16),
            showHideButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            showHideButton.widthAnchor.constraint(equalToConstant: CGFloat(48)),
            showHideButton.heightAnchor.constraint(equalToConstant: CGFloat(48)),
        ])
        
        // Touch Event
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(ViewController.handlePinch(_:)))
        view.addGestureRecognizer(pinchGesture)
        
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(ViewController.handlePan(_:)))
        panGesture.maximumNumberOfTouches = 1
        view.addGestureRecognizer(panGesture)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [] // Disable Embeded Plane Detection
        configuration.frameSemantics = [ .sceneDepth, .smoothedSceneDepth ]
        
        let options: ARSession.RunOptions = [ .resetTracking, .removeExistingAnchors ]

        // Run the view's session
        session.run(configuration, options: options)
        
        // The screen shouldn't dim during AR experiecnes.
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        session.pause()
    }
    
    // Auto-hide the home indicator to maximize immersion in AR experiences.
    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }
    
    // Hide the status bar to maximize immersion in AR experiences.
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    // MARK: - UI Event
    
    @objc
    private func viewValueChanged(view: UIView) {
        switch view {
            
        case confidenceControl:
            renderer.confidenceThreshold = confidenceControl.selectedSegmentIndex
            
        case smoothedControl:
            renderer.setSmoothedSceneDepth(useSmoothed: (smoothedControl.selectedSegmentIndex == 0))
            
        case sampleControl:
            renderer.setSamplingMethod(useFull: (sampleControl.selectedSegmentIndex == 0))
            
        case typeControl:
            findType = FindSurface.FeatureType.init(rawValue: UInt32(typeControl.selectedSegmentIndex))!
            
        default:
            break
        }
    }
    
    @objc
    private func onClickButton(view: UIView) {
        switch view {
        
        case findButton:
            findButton.isSelected = !findButton.isSelected // Toggle Button
            if findButton.isSelected { // onStartFindSurface
                captureButton.isHidden = false
            }
            else { // onStopFindSurface
                renderer.clearLiveMesh()
                captureButton.isHidden = true
            }
            
        case captureButton:
            if findButton.isSelected {
                renderer.appendLiveMesh()
            }
            
        case deleteButton:
            renderer.removeAllResultMesh()
            
        case undoButton:
            renderer.removeLastResultMesh()
            
        case showHideButton:
            showHideButton.isSelected = !showHideButton.isSelected // Toggle Button
            renderer.showPointCloud = !showHideButton.isSelected
            
        default:
            break
        }
    }
    
    // MARK: - Touch Event
    @objc
    func handlePinch(_ gesture: UIPinchGestureRecognizer) {
       if gesture.state == .changed {
            let velocity = Float(gesture.velocity)
            let factor: Float = 10
            
            touchRadiusPixel = simd_clamp( touchRadiusPixel + (velocity * factor), MIN_TOUCH_RADIUS_PIXEL, MAX_VIEW_RADIUS )
            if probeRadiusPixel > touchRadiusPixel {
                probeRadiusPixel = touchRadiusPixel
            }
            
            // Update to view
            updateTouchRadiusView()
            updateProbeRadiusView()
        }
    }
    
    @objc
    func handlePan(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .changed {
            let velocity = Float( gesture.velocity(in: view).y )
            let factor: Float = 0.01
            
            probeRadiusPixel = simd_clamp( probeRadiusPixel + (velocity * factor), MIN_PROBE_RADIUS_PIXEL, touchRadiusPixel )
            
            // Update to view
            updateProbeRadiusView()
        }
    }
    
    // MARK: - MTKViewDelegate
    
    // Called whenever view changes orientation or layout is changed
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        renderer.drawRectResized(size: size)
    }
    
    // Called whenever the view needs to render
    func draw(in view: MTKView) {
        if findButton.isSelected {
            findSurfaceTask()
        }
        
        renderer.update()
    }
    
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        
    }
    
    // MARK: - FindSurface
    
    func findSurfaceTask() {
        guard !isFindSurfaceBusy,
              let camera = session.currentFrame?.camera,
              let cache = renderer.copyPointCloudCacheWithConfidence() else { return }
        
        let viewSize = self.view.bounds.size
        let scaleFactor = viewSize.width < viewSize.height ? camera.projectionMatrix.columns.0.x : camera.projectionMatrix.columns.1.y
        let touchRadius = (touchRadiusPixel / MAX_VIEW_RADIUS) / scaleFactor
        let probeRadius = (probeRadiusPixel / MAX_VIEW_RADIUS) / scaleFactor
        
        let cameraTransform = camera.transform // Right-Handed
        let rayDirection    = -simd_make_float3( cameraTransform.columns.2 )
        let rayOrigin       =  simd_make_float3( cameraTransform.columns.3 )
        let targetType      = findType

        isFindSurfaceBusy = true
        fsTaskQueue.async {
            let pickIdx = pickPoint(rayDirection: rayDirection, rayPosition: rayOrigin, vertices: cache.pointCloud, count: cache.pointCount, probeRadius)
            if pickIdx >= 0
            {
                let pickPoint = simd_make_float3( cache.pointCloud[pickIdx] )
                let distance  = abs( simd_dot( (pickPoint - rayOrigin), rayDirection ) )
                let scaledTouchRadius = touchRadius * distance
                
                self.fsCtx.measurementAccuracy = 0.02 // measurement error is allowed about 2cm
                self.fsCtx.meanDistance = 0.2         // mean distance is maximum 20 cm
                
                self.fsCtx.setPointCloudData( UnsafeRawPointer( cache.pointCloud ),
                                              pointCount: cache.pointCount,
                                              pointStride: MemoryLayout<simd_float4>.stride,
                                              useDoublePrecision: false )
                
                do {
                    if let result = try self.fsCtx.findSurface(featureType: targetType, seedIndex: pickIdx, seedRadius: scaledTouchRadius, requestInlierFlags: false)
                    {
                        var resultUniform: InstanceUniforms? = nil
                        
                        switch result.type
                        {
                        case .plane:
                            let param = result.getAsPlaneResult()!
                            resultUniform = param.getInstanceUniform(withCameraTransform: cameraTransform)
                            
                        case .sphere:
                            let param = result.getAsSphereResult()!
                            resultUniform = param.getInstanceUniform(withCameraTransform: cameraTransform)
                            
                        case .cylinder:
                            let param = result.getAsCylinderResult()!
                            resultUniform = param.getInstanceUniform(withCameraTransform: cameraTransform)
                            
                        case .cone:
                            let param = result.getAsConeResult()!
                            resultUniform = param.getInstanceUniform(withCameraTransform: cameraTransform)
                            
                        case .torus:
                            let param = result.getAsTorusResult()!
                            resultUniform = param.getInstanceUniform(withCameraTransform: cameraTransform)
                            
                        default:
                            break; // Never Reach Here
                        }
                        
                        if let uniform = resultUniform {
                            DispatchQueue.main.async {
                                if self.findButton.isSelected {
                                    self.renderer.updateLiveMesh(uniform)
                                }
                            }
                        }
                    }
                    else {
                        // Not Found
                        DispatchQueue.main.async {
                            self.renderer.clearLiveMesh()
                        }
                    }
                }
                catch {
                    print("FindSurfaceError: \(error)")
                }
            }
            DispatchQueue.main.async {
                self.isFindSurfaceBusy = false
            }
        }
    }
    
    // MARK: - Update View Property
    func updateTouchRadiusView() {
        let td = CGFloat( 2.0 * touchRadiusPixel )
        touchRadiusView.layer.cornerRadius = CGFloat(touchRadiusPixel)
        
        touchRadiusWidthConstraint!.constant = td
        touchRadiusHeightConstraint!.constant = td
    }
    
    func updateProbeRadiusView() {
        let pd = CGFloat( 2.0 * probeRadiusPixel )
        probeRadiusView.layer.cornerRadius = CGFloat(probeRadiusPixel)
        
        probeRadiusWidthConstraint!.constant = pd
        probeRadiusHeightConstraint!.constant = pd
        
    }
}
