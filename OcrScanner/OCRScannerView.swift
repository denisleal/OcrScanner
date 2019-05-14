//
//  OCRScannerView.swift
//  OCRScanner
//
//  Created by admdenlea01 on 2019-05-06.
//  Copyright © 2019 Marginalen Bank. All rights reserved.
//

import UIKit
import AVFoundation
import FirebaseMLVision

public protocol OCRScannerViewDelegate: class {
    func didRecognizeOcrNumber(_ ocrNumber: String)
    func didRecognizeGiroNumber(_ giroNumber: String)
    func didRecognizeAmount(_ amount: Double)
}

public class OCRScannerView: UIView {
    weak var delegate: OCRScannerViewDelegate?

    private lazy var videoDataOutput: AVCaptureVideoDataOutput = {
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        videoDataOutput.connection(with: .video)?.isEnabled = true
        return videoDataOutput
    }()

    private let videoDataOutputQueue: DispatchQueue = DispatchQueue(label: "DataOutputQueue")
    private lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }()

    private lazy var vision = Vision.vision()

    private let captureDevice: AVCaptureDevice? = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    private lazy var session: AVCaptureSession = {
        let session = AVCaptureSession()
        session.sessionPreset = .hd1280x720
        return session
    }()

    private var timer: Timer?
    private var allowFrameCapture = true

    enum OCRType {
        case reference
        case amount
        case giroNr
        case undefined
    }

    typealias OCRResult = (type: OCRType, value: String, amount: Double, isValid: Bool)

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)

        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        commonInit()
    }

    private func commonInit() {
        contentMode = .scaleAspectFit
    }

    // MARK: - Override

    override public func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }

    deinit {
        endSession()
    }

    // MARK: - Public

    public func beginSession() {
        do {
            guard let captureDevice = captureDevice else {
                fatalError("Camera doesn't work on the simulator! You have to test this on an actual device!")
            }
            let deviceInput = try AVCaptureDeviceInput(device: captureDevice)
            if session.canAddInput(deviceInput) {
                session.addInput(deviceInput)
            }

            if session.canAddOutput(videoDataOutput) {
                session.addOutput(videoDataOutput)
            }

            layer.masksToBounds = true
            previewLayer.frame = bounds
            layer.addSublayer(previewLayer)

            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { [weak self] _ in
                self?.allowFrameCapture = true
            })

            session.startRunning()

        } catch let error {
            debugPrint("\(self.self): \(#function) line: \(#line).  \(error.localizedDescription)")
        }
    }

    public func endSession() {
        timer?.invalidate()
        session.stopRunning()
    }

    // MARK: - Private

    private func recognizeTextOnDevice(in image: VisionImage, width: CGFloat, height: CGFloat) {
        let textRecognizer = vision.onDeviceTextRecognizer()
        textRecognizer.process(image) { result, error in
            guard error == nil, let result = result else {
                return
            }
            let text = result.blocks.compactMap({ (block) -> String? in
                return block.text
            }).joined(separator: " ")
//            print(text)
            self.analyzeRecognizedText(text)
        }
    }

    private func analyzeRecognizedText(_ text: String) {
        for result in self.checkStringForOCR(string: text) {
            DispatchQueue.main.async {
                switch result.type {
                case .reference where result.isValid:
                    print("\n============================")
                    print("Found OCR Number: \(result.value)")
                    print("============================\n")
                    self.delegate?.didRecognizeOcrNumber(result.value)

                case .amount where result.isValid:
                    print("\n============================")
                    print("Found Amount: \(result.amount)")
                    print("============================\n")
                    self.delegate?.didRecognizeAmount(result.amount)

                case .giroNr:
                    print("\n============================")
                    print("Found Giro Number: \(result.value)")
                    print("============================\n")
                    self.delegate?.didRecognizeGiroNumber(result.value)

                default:
                    //print(result)
                    break
                }
            }
        }
    }

    //swiftlint:disable large_tuple
    private func checkStringForOCR(string: String) -> [OCRResult] {
        let giroPattern = "[0-9]{2,8}#[0-9]{2}#"
        let amountPattern = "(^|\\s)[0-9]{0,7}\\s[0-9]{1,2}\\s[0-9]{1}(\\s|$)"
        let ocrNrPattern = "[0-9]{3,25}\\s#(\\s|$)"

        var results: [OCRResult] = []

        if !string.matches(for: ocrNrPattern).isEmpty {
//            print(string)
            let ocrText = string.matches(for: ocrNrPattern).first ?? ""
            results.append(OCRResult(type: .reference,
                                     value: formatOCRNumber(ocrText),
                                     amount: 0,
                                     isValid: checkValid10Modulus(string: ocrText, controlLength: false)))
        }

        if !string.matches(for: amountPattern).isEmpty {
//            print(string)
            let amountText = string.matches(for: amountPattern).first ?? ""
            results.append(OCRResult(type: .amount,
                                     value: string,
                                     amount: formatAmount(amountText),
                                     isValid: checkValid10Modulus(string: amountText.replacingOccurrences(of: " ", with: ""), controlLength: false)))
        }

        if !string.matches(for: giroPattern).isEmpty {
//            print(string)
            let giroText = string.matches(for: giroPattern).first ?? ""
            results.append(OCRResult(type: .giroNr, value: formatGiroNumber(giroText), amount: 0, isValid: true))
        }

        return results
    }

    private func formatOCRNumber(_ ocrText: String) -> String {
        guard let formatted = ocrText.split(separator: "#").first else { return ocrText }
        return String(formatted).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatAmount(_ amountText: String) -> Double {
        let parts = amountText.split(separator: " ")
        let amountText = String(parts[0] + "," + parts[1])
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.decimalSeparator = ","
        return formatter.number(from: amountText)?.doubleValue ?? 0
    }

    private func formatGiroNumber(_ giroText: String) -> String {
        guard let formatted = giroText.split(separator: "#").first else { return giroText }
        return String(formatted)
    }

    /// This function calculates if a OCR-number is valid according to 10 modulus.
    ///
    /// - Parameters:
    ///   - string: String containing OCR-number
    ///   - controlLength: If string lenght should also be valid according to OCR standard
    /// - Returns: Bool saying if the OCR is valid or not
    private func checkValid10Modulus(string: String, controlLength: Bool) -> Bool {

        var total = 0
        var multiplyByOne = false
        var controlNr = 0
        let lengthNr = (string.count - 1) % 10
        let reversedString = string.replacingOccurrences(of: "#", with: "",
                                                         options: .literal, range: nil)
            .replacingOccurrences(of: " ", with: "",
                                  options: .literal, range: nil).reversed()
        for (index, char) in reversedString.enumerated() {
            let stringChar = String(char)
            guard let intChar = Int(stringChar) else {
                return false }
            if index == 0 { controlNr = intChar; continue }
            let multiplied = multiplyByOne ? intChar * 1 : intChar * 2
            if multiplied >= 10 {
                total += multiplied - 9
            } else {
                total += multiplied
            }
            multiplyByOne = !multiplyByOne
        }

        let calculatedControlNr = (10 - total % 10)

        if controlLength {
            var writableIncomingString = string
            let newCtrlNr = writableIncomingString.remove(at: string.index(before: string.index(string.endIndex, offsetBy: -1)))
            guard let controlLengthInt = Int(String(newCtrlNr)) else {
                return false }

            if lengthNr == controlLengthInt && controlNr == calculatedControlNr {
                return true
            }
        } else if controlNr == calculatedControlNr {
            return true
        }
        return false
    }
}

extension OCRScannerView: AVCaptureVideoDataOutputSampleBufferDelegate {

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer), allowFrameCapture else { return }
        allowFrameCapture = false
        let fullImage = imageFromSampleBuffer(sampleBuffer: sampleBuffer)
        if let image = cropToPreviewLayer(originalImage: fullImage) {
            let visionImage = VisionImage(image: image)
            let metadata = VisionImageMetadata()
            metadata.orientation = .rightTop
            visionImage.metadata = metadata
            let imageWidth = CGFloat(CVPixelBufferGetWidth(imageBuffer))
            let imageHeight = CGFloat(CVPixelBufferGetHeight(imageBuffer))
            self.recognizeTextOnDevice(in: visionImage, width: imageWidth, height: imageHeight)
        }
    }

    private func imageFromSampleBuffer(sampleBuffer : CMSampleBuffer) -> UIImage {
        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
        let ciimage = CIImage(cvPixelBuffer: imageBuffer)
        let image = convert(ciImage: ciimage)
        return image
    }

    private func convert(ciImage: CIImage) -> UIImage {
        let context = CIContext(options: nil)
        let cgImage = context.createCGImage(ciImage, from: ciImage.extent)!
        let image = UIImage(cgImage: cgImage)
        return image
    }

    private func cropToPreviewLayer(originalImage: UIImage) -> UIImage? {
        guard let cgImage = originalImage.cgImage else { return nil }
        let outputRect = previewLayer.metadataOutputRectConverted(fromLayerRect: previewLayer.bounds)
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let cropRect = CGRect(x: outputRect.origin.x * width,
                              y: outputRect.origin.y * height,
                              width: outputRect.size.width * width,
                              height: outputRect.size.height * height)
        if let croppedCGImage = cgImage.cropping(to: cropRect) {
            return UIImage(cgImage: croppedCGImage, scale: originalImage.scale, orientation: originalImage.imageOrientation)
        }
        return nil
    }
}

extension String {
    func matches(for regex: String) -> [String] {
        do {
            let regex = try NSRegularExpression(pattern: regex)
            let results = regex.matches(in: self,
                                        range: NSRange(self.startIndex..., in: self))
            return results.map {
                String(self[Range($0.range, in: self)!])
            }
        } catch let error {
            print("invalid regex: \(error.localizedDescription)")
            return []
        }
    }
}
