//
//  BarcodeScannerView.swift
//  PlotLine
//

import SwiftUI
import AVFoundation

struct BarcodeScannerView: UIViewControllerRepresentable {
    let onBarcodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let vc = BarcodeScannerViewController()
        vc.onBarcodeScanned = onBarcodeScanned
        return vc
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {}
}

class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onBarcodeScanned: ((String) -> Void)?
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasScanned = false

    // Overlay views
    private let overlayView = UIView()
    private let scanWindow = UIView()
    private let instructionLabel = UILabel()

    // Scan region relative to view (centered rectangle)
    private let scanRegionSize = CGSize(width: 280, height: 280)

    private var scanWindowRect: CGRect {
        let x = (view.bounds.width - scanRegionSize.width) / 2
        let y = (view.bounds.height - scanRegionSize.height) / 2 - 40
        return CGRect(x: x, y: y, width: scanRegionSize.width, height: scanRegionSize.height)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        setupOverlay()
    }

    private func setupCamera() {
        let session = AVCaptureSession()

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            showError("Camera not available")
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.ean8, .ean13, .upce, .code128, .code39, .code93, .itf14]
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        self.previewLayer = preview

        captureSession = session
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    private func setupOverlay() {
        let windowRect = scanWindowRect

        // Dimmed overlay covering the full screen
        overlayView.frame = view.bounds
        overlayView.backgroundColor = .clear
        overlayView.isUserInteractionEnabled = false
        view.addSubview(overlayView)
        addDimMask(to: overlayView, cutout: windowRect)

        // Scan window border
        scanWindow.frame = windowRect
        scanWindow.backgroundColor = .clear
        scanWindow.layer.cornerRadius = 12
        scanWindow.layer.borderWidth = 2.5
        scanWindow.layer.borderColor = UIColor.white.cgColor
        view.addSubview(scanWindow)

        // Corner accents
        addCornerAccents(to: scanWindow)

        // Instruction label
        instructionLabel.text = "Align barcode within the frame"
        instructionLabel.textColor = .white
        instructionLabel.font = .systemFont(ofSize: 15, weight: .medium)
        instructionLabel.textAlignment = .center
        instructionLabel.frame = CGRect(x: 0, y: windowRect.maxY + 20, width: view.bounds.width, height: 24)
        view.addSubview(instructionLabel)

        // Scan line animation
        let scanLine = UIView()
        scanLine.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.6)
        scanLine.frame = CGRect(x: 8, y: 0, width: scanRegionSize.width - 16, height: 2)
        scanLine.layer.cornerRadius = 1
        scanWindow.addSubview(scanLine)

        UIView.animate(withDuration: 2.0, delay: 0, options: [.repeat, .autoreverse, .curveEaseInOut]) {
            scanLine.frame.origin.y = self.scanRegionSize.height - 2
        }
    }

    private func addDimMask(to targetView: UIView, cutout: CGRect) {
        let maskLayer = CAShapeLayer()
        let fullPath = UIBezierPath(rect: targetView.bounds)
        let cutoutPath = UIBezierPath(roundedRect: cutout, cornerRadius: 12)
        fullPath.append(cutoutPath)
        fullPath.usesEvenOddFillRule = true
        maskLayer.path = fullPath.cgPath
        maskLayer.fillRule = .evenOdd
        maskLayer.fillColor = UIColor.black.withAlphaComponent(0.55).cgColor
        targetView.layer.addSublayer(maskLayer)
    }

    private func addCornerAccents(to containerView: UIView) {
        let cornerLength: CGFloat = 24
        let cornerWidth: CGFloat = 3.5
        let color = UIColor.systemBlue.cgColor

        let w = containerView.bounds.width
        let h = containerView.bounds.height

        for (x, y, cw, ch) in [
            // Top-left
            (CGFloat(0), CGFloat(0), cornerLength, cornerWidth),
            (CGFloat(0), CGFloat(0), cornerWidth, cornerLength),
            // Top-right
            (w - cornerLength, CGFloat(0), cornerLength, cornerWidth),
            (w - cornerWidth, CGFloat(0), cornerWidth, cornerLength),
            // Bottom-left
            (CGFloat(0), h - cornerWidth, cornerLength, cornerWidth),
            (CGFloat(0), h - cornerLength, cornerWidth, cornerLength),
            // Bottom-right
            (w - cornerLength, h - cornerWidth, cornerLength, cornerWidth),
            (w - cornerWidth, h - cornerLength, cornerWidth, cornerLength),
        ] {
            let layer = CALayer()
            layer.frame = CGRect(x: x, y: y, width: cw, height: ch)
            layer.backgroundColor = color
            layer.cornerRadius = cornerWidth / 2
            containerView.layer.addSublayer(layer)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds

        let windowRect = scanWindowRect
        scanWindow.frame = windowRect
        overlayView.frame = view.bounds
        overlayView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        addDimMask(to: overlayView, cutout: windowRect)

        instructionLabel.frame = CGRect(x: 0, y: windowRect.maxY + 20, width: view.bounds.width, height: 24)
    }

    // MARK: - Barcode detection

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !hasScanned,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let barcode = object.stringValue,
              let preview = previewLayer else { return }

        // Convert barcode bounds from camera coordinates to view coordinates
        guard let transformed = preview.transformedMetadataObject(for: object) else { return }

        // Only accept if the barcode center is inside the scan window
        let barcodeCenterY = transformed.bounds.midY
        let barcodeCenterX = transformed.bounds.midX
        let windowRect = scanWindowRect

        guard windowRect.contains(CGPoint(x: barcodeCenterX, y: barcodeCenterY)) else { return }

        hasScanned = true
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))

        // Flash the scan window green briefly
        UIView.animate(withDuration: 0.15, animations: {
            self.scanWindow.layer.borderColor = UIColor.systemGreen.cgColor
            self.scanWindow.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.15)
        }) { _ in
            self.captureSession?.stopRunning()
            self.onBarcodeScanned?(barcode)
        }
    }

    private func showError(_ message: String) {
        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.textAlignment = .center
        label.frame = view.bounds
        view.addSubview(label)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }
}
