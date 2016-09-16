//
//  NoInternetFoundViewController.swift
//  FeedReader
//
//  Created by Saurav Bhattacharya on 9/15/16.
//  Copyright © 2016 InstaRead Inc. All rights reserved.
//

import UIKit

class NoInternetFoundViewController: UIViewController {

    // Dismiss the no internet view controller once internet connection has been found.
    @IBAction func retryInternetButton(sender: AnyObject) {
        if Reachability.isConnectedToNetwork() == true {            
            dismissViewControllerAnimated(true, completion: nil)
        }
    }
}
