//
//  ViewController.swift
//  UDPBroadcastExample
//
//  Created by Gunter Hager on 10.02.16.
//  Copyright © 2016 Gunter Hager. All rights reserved.
//

import UIKit
import UDPBroadcast

class ViewController: UIViewController {
    
    @IBOutlet var logView: UITextView!
    
    var broadcastConnection: UDPv4BroadcastConnection!
    var broadcastConnectionv6: UDPv6BroadcastConnection!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        logView.text = "UDP Broadcast: tap on reload button to start sending.\n\n"
        
        do {
            broadcastConnection = try UDPv4BroadcastConnection(port: Config.Ports.broadcast, handler: responseHandler, errorHandler: errorHandler)
            broadcastConnectionv6 = try UDPv6BroadcastConnection(port: Config.Ports.broadcast, handler: responseHandler, errorHandler: errorHandler)
        } catch {
            log("Error: \(error)\n")
        }
    }
    
    fileprivate func responseHandler(ipAddress: String, port: Int, response: Data) {
        let hexString = self.hexBytes(data: response)
        let utf8String = String(data: response, encoding: .utf8) ?? ""
        print("UDP connection received from \(ipAddress):\(port):\n\(hexString)\n\(utf8String)\n")
        self.log("Received from \(ipAddress):\(port):\n\(hexString)\n\(utf8String)\n")
    }
    
    fileprivate func errorHandler(error: UDPBroadcastConnection.ConnectionError) {
        self.log("Error: \(error)\n")
    }

    private func hexBytes(data: Data) -> String {
        return data
            .map { String($0, radix: 16, uppercase: true) }
            .joined(separator: ", ")
    }
    
    
    @IBAction func reload(_ sender: AnyObject) {
        log("")
        do {
            try broadcastConnectionv6.sendBroadcast(message: Config.Strings.broadcastMessage)
            try broadcastConnection.sendBroadcast(message: Config.Strings.broadcastMessage)

            log("Sent: '\(Config.Strings.broadcastMessage)'\n")
        } catch {
            log("Error: \(error)\n")
        }
    }
    
    private func log(_ message: String) {
        self.logView.text += message
    }
    
}
