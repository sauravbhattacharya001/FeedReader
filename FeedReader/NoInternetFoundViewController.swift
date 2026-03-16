//
//  NoInternetFoundViewController.swift
//  FeedReader
//
//  Created by Saurav Bhattacharya on 9/15/16.
//  Copyright © 2016 InstaRead Inc. All rights reserved.
//

import UIKit

/// View controller displayed when no internet connection is detected.
///
/// Presents a retry button that dismisses the view once connectivity is restored.
class NoInternetFoundViewController: UIViewController {
    // MARK: - Actions
    
    /// Checks network reachability and dismisses this view controller if connected.
    ///
    /// Called when the user taps the retry button. If the network is still
    /// unreachable, the view remains visible so the user can try again.
    @IBAction func retryInternetButton(_ sender: AnyObject) {
        if Reachability.isConnectedToNetwork() == true {            
            dismiss(animated: true, completion: nil)
        }
    }
}
