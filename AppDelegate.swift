//
//  AppDelegate.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 5/6/26.
//


import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        // Support all orientations
        return .allButUpsideDown
    }
}