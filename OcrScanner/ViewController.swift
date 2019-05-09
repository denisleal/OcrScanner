//
//  ViewController.swift
//  OcrScannerExample
//
//  Created by admdenlea01 on 2019-05-07.
//  Copyright © 2019 Knowit Mobile Stockholm. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    @IBOutlet weak var ocrScannerView: OCRScannerView!
    @IBOutlet weak var ocrInfoView: UIView!
    @IBOutlet weak var ocrLabel: UILabel!
    @IBOutlet weak var sumLbl: UILabel!
    @IBOutlet weak var giroLbl: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        ocrScannerView.delegate = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ocrScannerView.beginSession()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        ocrScannerView.endSession()
    }

    @IBAction func didTapReset(_ sender: Any) {
        ocrLabel.text = "0"
        sumLbl.text = "0"
        giroLbl.text = "0"
    }
}

extension ViewController: OCRScannerViewDelegate {
    func didRecognizeOcrNumber(_ ocrNumber: String) {
        self.ocrLabel.text = ocrNumber
    }

    func didRecognizeGiroNumber(_ giroNumber: String) {
        self.giroLbl.text = giroNumber
    }

    func didRecognizeAmount(_ amount: Double) {
        self.sumLbl.text = amount.description
    }
}
