import SwiftUI
import AVFoundation
import Vision
import AppKit

class CameraViewModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Rectangles normalisés dans le repère de la preview (origine EN HAUT-GAUCHE, 0–1)
    @Published var detectedRects: [CGRect] = []

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let videoQueue = DispatchQueue(label: "camera.video.queue")

    /// Référence vers la previewLayer (remplie par CameraPreview)
    weak var previewLayer: AVCaptureVideoPreviewLayer?

    override init() {
        super.init()
        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        // Sur macOS, on prend simplement le device vidéo par défaut
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)

        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(videoOutput)

        session.commitConfiguration()
    }

    func startSession() {
        sessionQueue.async {
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stopSession() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    // MARK: - Delegate

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectHumanRectanglesRequest { [weak self] req, _ in
            guard let self = self else { return }
            guard let previewLayer = self.previewLayer else { return }

            let results = (req.results as? [VNHumanObservation]) ?? []
            let bounds = previewLayer.bounds

            let rects: [CGRect] = results.compactMap { obs in
                let vBox = obs.boundingBox   // Vision (0–1), origine bas-gauche

                // 1) passer en "metadata" (0–1, origine haut-gauche)
                let metaRect = CGRect(
                    x: vBox.origin.x,
                    y: 1.0 - vBox.origin.y - vBox.size.height,
                    width: vBox.size.width,
                    height: vBox.size.height
                )

                // 2) convertit en coordonnées CALayer (en points)
                let layerRect = previewLayer.layerRectConverted(fromMetadataOutputRect: metaRect)

                // 3) normaliser dans le repère de la previewLayer (origine haut-gauche, 0–1)
                guard bounds.width > 0, bounds.height > 0 else { return nil }

                let normRect = CGRect(
                    x: layerRect.origin.x / bounds.width,
                    y: layerRect.origin.y / bounds.height,
                    width: layerRect.size.width / bounds.width,
                    height: layerRect.size.height / bounds.height
                )
                return normRect
            }

            DispatchQueue.main.async {
                self.detectedRects = rects
            }
        }

        // Orientation du buffer (à ajuster si besoin selon la config)
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: .up,
                                            options: [:])
        try? handler.perform([request])
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    @ObservedObject var model: CameraViewModel

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true   // indispensable pour avoir une CALayer

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds

        view.layer?.addSublayer(previewLayer)

        // On donne la layer au ViewModel pour la conversion des rects
        model.previewLayer = previewLayer

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let previewLayer = model.previewLayer else { return }
        previewLayer.frame = nsView.bounds
    }
}
