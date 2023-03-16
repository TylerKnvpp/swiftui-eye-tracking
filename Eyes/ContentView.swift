//
//  ContentView.swift
//  Eyes
//
//  Created by Tyler Knapp on 3/16/23.
//

import SwiftUI
import CoreData
import AVFoundation
import Vision

struct ContentView: View {
    @StateObject var viewModel = EyeTrackingViewModel()

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            CameraViewControllerRepresentable(viewModel: viewModel)
                .ignoresSafeArea()
                .opacity(0)

            if !viewModel.isCenterPositionSet {
                Circle()
                    .fill(Color.green)
                    .frame(width: 20, height: 20)
                    .position(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY)

                Text("Please look at the center of the screen")
                    .foregroundColor(.white)
                    .position(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY - 30)
            } else {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 50, height: 50)
                    .position(viewModel.position)
                    .edgesIgnoringSafeArea(.all)
            }

            VStack {
                Text("X: \(viewModel.position.x, specifier: "%.2f")")
                    .foregroundColor(.white)
                Text("Y: \(viewModel.position.y, specifier: "%.2f")")
                    .foregroundColor(.white)
                if viewModel.isCenterPositionSet {
                    Text("Center X: \(viewModel.centerPosition.x, specifier: "%.2f")")
                        .foregroundColor(.white)
                    Text("Center Y: \(viewModel.centerPosition.y, specifier: "%.2f")")
                        .foregroundColor(.white)
                }
            }
            .position(x: UIScreen.main.bounds.midX, y: 30)
        }
        .onAppear {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    viewModel.cameraAccessGranted = true
                } else {
                    print("Camera access not granted")
                }
            }
        }
    }
}

class CameraViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    var viewModel: EyeTrackingViewModel

    private let captureSession = AVCaptureSession()
    private var leftEyeRequest = VNDetectFaceLandmarksRequest()
    private var rightEyeRequest = VNDetectFaceLandmarksRequest()

    init(viewModel: EyeTrackingViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupFrontCamera()
        DispatchQueue.global().async {
            self.captureSession.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        DispatchQueue.global().async {
            self.captureSession.stopRunning()
        }
    }

    private func setupFrontCamera() {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else { return }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))

            captureSession.sessionPreset = .high
            captureSession.addInput(input)
            captureSession.addOutput(output)
        } catch {
            print("Error setting up front camera: \(error)")
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try imageRequestHandler.perform([leftEyeRequest, rightEyeRequest])

            guard let leftEye = leftEyeRequest.results?.first as? VNFaceObservation,
                  let rightEye = rightEyeRequest.results?.first as? VNFaceObservation else { return }

            DispatchQueue.main.async {
                let leftEyePosition = self.getEyePosition(on: leftEye)
                let rightEyePosition = self.getEyePosition(on: rightEye)

                let eyePosition = CGPoint(x: (leftEyePosition.x + rightEyePosition.x) / 2,
                                          y: (leftEyePosition.y + rightEyePosition.y) / 2)

                if !self.viewModel.isCenterPositionSet {
                    self.viewModel.setCenterPosition(eyePosition: eyePosition)
                } else {
                    self.viewModel.position = CGPoint(x: eyePosition.y * UIScreen.main.bounds.width,
                                                      y: (1 - eyePosition.x) * UIScreen.main.bounds.height)
                }
            }
        } catch {
            print("Error detecting eye landmarks: \(error)")
        }
    }

    private func getEyePosition(on faceObservation: VNFaceObservation) -> CGPoint {
        guard let leftEye = faceObservation.landmarks?.leftEye,
              let rightEye = faceObservation.landmarks?.rightEye else { return CGPoint(x: 0.5, y: 0.5) }

        let leftEyePoints = leftEye.pointsInImage(imageSize: CGSize(width: 1, height: 1))
        let rightEyePoints = rightEye.pointsInImage(imageSize: CGSize(width: 1, height: 1))

        let leftEyePosition = CGPoint.average(points: leftEyePoints)
        let rightEyePosition = CGPoint.average(points: rightEyePoints)

//        let eyePosition = CGPoint(x: (leftEyePosition.x + rightEyePosition.x))
        let eyePosition = CGPoint(x: (leftEyePosition.x + rightEyePosition.x) / 2, y: (leftEyePosition.y + rightEyePosition.y) / 2)

        return eyePosition
    }

}

struct CameraViewControllerRepresentable: UIViewControllerRepresentable {
    var viewModel: EyeTrackingViewModel

    func makeUIViewController(context: Context) -> CameraViewController {
        CameraViewController(viewModel: viewModel)
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}

class EyeTrackingViewModel: NSObject, ObservableObject {
    @Published var position: CGPoint = CGPoint(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY)
    @Published var cameraAccessGranted: Bool = false {
        didSet {
            if cameraAccessGranted {
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                }
            }
        }
    }
    
    var isCenterPositionSet: Bool = false
    var centerPosition: CGPoint = CGPoint(x: 0.5, y: 0.5)
    
    func setCenterPosition(eyePosition: CGPoint) {
            centerPosition = eyePosition
            isCenterPositionSet = true
        }

    func getRelativeEyePosition(eyePosition: CGPoint) -> CGPoint {
        return CGPoint(x: eyePosition.x - centerPosition.x, y: eyePosition.y - centerPosition.y)
    }

    override init() {
        super.init()
        requestCameraAccess()
    }

    func requestCameraAccess() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                self?.cameraAccessGranted = granted
            }
        }
    }
}

extension CGPoint {
    static func +(lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        return CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func average(points: [CGPoint]) -> CGPoint {
        let total = points.reduce(CGPoint.zero, +)
        return CGPoint(x: total.x / CGFloat(points.count), y: total.y / CGFloat(points.count))
    }
}
