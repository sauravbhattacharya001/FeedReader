//
//  UIViewController+Toast.swift
//  FeedReader
//
//  Reusable toast notification for any view controller. Extracted from
//  StoryTableViewController to eliminate duplication as more screens
//  need brief confirmation messages.
//

import UIKit

extension UIViewController {

    /// Display a brief toast message at the bottom of the screen.
    ///
    /// The toast fades in, stays visible for `duration` seconds, then
    /// fades out and removes itself from the view hierarchy.
    ///
    /// - Parameters:
    ///   - message: Text to display.
    ///   - duration: How long the toast remains visible (default: 1.2s).
    func showToast(_ message: String, duration: TimeInterval = 1.2) {
        let toastLabel = UILabel()
        toastLabel.text = message
        toastLabel.textAlignment = .center
        toastLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        toastLabel.textColor = .white
        toastLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        toastLabel.layer.cornerRadius = 16
        toastLabel.clipsToBounds = true
        toastLabel.alpha = 0

        let textSize = toastLabel.intrinsicContentSize
        let width = textSize.width + 40
        let height: CGFloat = 36
        toastLabel.frame = CGRect(
            x: (view.frame.width - width) / 2,
            y: view.frame.height - 120,
            width: width,
            height: height
        )

        view.addSubview(toastLabel)

        UIView.animate(withDuration: 0.3, animations: {
            toastLabel.alpha = 1
        }) { _ in
            UIView.animate(withDuration: 0.3, delay: duration, options: [], animations: {
                toastLabel.alpha = 0
            }) { _ in
                toastLabel.removeFromSuperview()
            }
        }
    }
}
