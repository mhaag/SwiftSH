//
//  SCPViewController.swift
//  SwiftSH Example
//
//  Created by Markus Haag on 25.06.20.
//  Copyright © 2020 Tommaso Madonia. All rights reserved.
//

import Foundation
import UIKit
import SwiftSH

class SCPViewController: UIViewController, SSHViewController {
    
    @IBOutlet weak var hostTextLabel: UILabel!
    @IBOutlet weak var scpOutputTextView: UITextView!
    
    var authenticationChallenge: AuthenticationChallenge?
    var semaphore: DispatchSemaphore!
    var passwordTextField: UITextField?
    
    var requiresAuthentication = false
    var hostname: String!
    var port: UInt16?
    var username: String!
    var password: String?
    
    var scp: SCPSession!
    var scpOutput: String!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if self.requiresAuthentication {
            if let password = self.password {
                self.authenticationChallenge = .byPassword(username: self.username, password: password)
            } else {
                self.authenticationChallenge = .byKeyboardInteractive(username: self.username) { [unowned self] challenge in
                    DispatchQueue.main.async {
                        self.askForPassword(challenge)
                    }
                    
                    self.semaphore = DispatchSemaphore(value: 0)
                    _ = self.semaphore.wait(timeout: DispatchTime.distantFuture)
                    self.semaphore = nil
                    
                    return self.password ?? ""
                }
            }
        }
        
        
        self.hostTextLabel.text = self.hostname
        
        self.scpOutputTextView.text = ""
        
        self.scpOutput = "Nothing received"
        
        self.scp = try? SCPSession(host: self.hostname)
        
    }
    
    @IBAction func readJsonFile(_ sender: Any) {
        print("Read File started...")
        self.scp
            .connect().authenticate(self.authenticationChallenge)
        self.scp.download("config.json", to: self.scpOutput)
        self.scpOutputTextView.text = self.scpOutput
        
    }

    @IBAction func disconnect(_ sender: Any) {
        self.scp?.disconnect { [unowned self] in
            self.navigationController?.popViewController(animated: true)
        }
    }
    
    func askForPassword(_ challenge: String) {
        let alertController = UIAlertController(title: "Authetication challenge", message: challenge, preferredStyle: .alert)
        alertController.addTextField { [unowned self] (textField) in
            textField.placeholder = challenge
            textField.isSecureTextEntry = true
            self.passwordTextField = textField
        }
        alertController.addAction(UIAlertAction(title: "OK", style: .default) { [unowned self] _ in
            self.password = self.passwordTextField?.text
            if let semaphore = self.semaphore {
                semaphore.signal()
            }
        })
        self.present(alertController, animated: true, completion: nil)
    }
    
}
