//
//  KeyboardDismisser.swift
//  PlotLine
//
//  Tapping anywhere outside a text field closes the keyboard, on every screen (sheets included).
//  One tap recognizer sits on the app's window; it never blocks the tap, so buttons, rows and
//  pickers still get it, and taps on another text field just move the cursor there.
//

import SwiftUI
import UIKit

struct KeyboardDismisser: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView { InstallerView() }
    func updateUIView(_ uiView: InstallerView, context: Context) {}

    final class InstallerView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, !(window.gestureRecognizers ?? []).contains(where: { $0 is TapRecognizer }) else { return }
            window.addGestureRecognizer(TapRecognizer())
        }
    }

    final class TapRecognizer: UITapGestureRecognizer, UIGestureRecognizerDelegate {
        init() {
            super.init(target: nil, action: nil)
            addTarget(self, action: #selector(tapped))
            cancelsTouchesInView = false
            delaysTouchesEnded = false
            delegate = self
        }

        @objc private func tapped() {
            view?.endEditing(true)
        }

        // leave taps on text fields alone (that's how you move between fields)
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
