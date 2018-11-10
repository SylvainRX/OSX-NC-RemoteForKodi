//
//  ViewController.swift
//  Kodi Remote
//
//  Created by Sylvain Roux on 2018-10-10.
//  Copyright © 2018 Sylvain Roux. All rights reserved.
//

import Cocoa

class ViewController: NSViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }

    @IBAction func onOk(sender: NSButton) {
        NSApp.terminate(self)
    }
}

