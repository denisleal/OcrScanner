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
    func didRecognizeAmount(_ amount: String)
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
        textRecognizer.process(image) { text, error in
            guard error == nil, let text = text else {
                return
            }
            for block in text.blocks {
                print(block.text)
                let result = self.checkStringForOCR(string: block.text)

                DispatchQueue.main.async {
                    if result.0 == .giroNr {
                        self.delegate?.didRecognizeGiroNumber(result.1)
                    } else if result.0 == .reference && result.2 == true {
                        self.delegate?.didRecognizeOcrNumber(result.1)
                    } else if result.0 == .amount {
                        self.delegate?.didRecognizeAmount(result.1)
                    } else if result.0 == .undefined {
                        //print("type: \(result.0), text: \(result.1), bool: \(result.2)")
                    }
                }
            }
        }
    }

    //swiftlint:disable large_tuple
    private func checkStringForOCR(string: String) -> (OCRType, String, Bool) {
        let giroPattern = "[0-9]{2,8}#[0-9]{2}#"
        let amountPattern = "[0-9]{0,7}\\s[0-9]{2}"
        let ocrNrPattern = "[0-9]{3,25}\\s#"

        let predicateGiro = NSPredicate(format: "SELF MATCHES %@", giroPattern)
        let predicateAmount = NSPredicate(format: "SELF MATCHES %@", amountPattern)
        let predicateOCRNr = NSPredicate(format: "SELF MATCHES %@", ocrNrPattern)

        if predicateOCRNr.evaluate(with: string) {
            return (.reference, string, checkValidOCRNr(string: string, controlLength: false))
        } else if predicateAmount.evaluate(with: string) {
            return (.amount, string, false)
        } else if predicateGiro.evaluate(with: string) {
            return (.giroNr, string, false)
        } else {
            return (.undefined, string, false)
        }
    }

    /// This function calculates if a OCR-number is valid according to 10 modulus.
    ///
    /// - Parameters:
    ///   - string: String containing OCR-number
    ///   - controlLength: If string lenght should also be valid according to OCR standard
    /// - Returns: Bool saying if the OCR is valid or not
    private func checkValidOCRNr(string: String, controlLength: Bool) -> Bool {

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
        print(Date())
        let visionImage = VisionImage(buffer: sampleBuffer)
        let metadata = VisionImageMetadata()
        let visionOrientation = VisionDetectorImageOrientation.rightTop
        metadata.orientation = visionOrientation
        visionImage.metadata = metadata
        let imageWidth = CGFloat(CVPixelBufferGetWidth(imageBuffer))
        let imageHeight = CGFloat(CVPixelBufferGetHeight(imageBuffer))
        self.recognizeTextOnDevice(in: visionImage, width: imageWidth, height: imageHeight)
    }
}
