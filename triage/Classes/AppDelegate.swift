//
//  AppDelegate.swift
//  triage
//
//  Created by Christopher Kintner on 3/4/15.
//  Copyright (c) 2015 Christopher Kintner. All rights reserved.
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

  let API = ZendeskAPI.instance
  let userCache = UserCache()

  var window: UIWindow?
  var storyboard = UIStoryboard(name: "Main", bundle: nil)

  func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
    let credential = AFOAuthCredential.retrieveCredentialWithIdentifier(
      APICredentialID
    )

    NSNotificationCenter.defaultCenter().addObserver(
      self,
      selector: "userDidLogout",
      name: "userDidLogoutNotification",
      object: nil
    )

    if (credential != nil) {
      UserFields.refreshCurrentUser()
      API.requestSerializer.setAuthorizationHeaderFieldWithCredential(credential)

      window!.rootViewController = storyboard.instantiateViewControllerWithIdentifier(
        "TicketsViewController"
      ) as TicketsViewController
    } else {
      window!.rootViewController = (storyboard.instantiateInitialViewController() as UIViewController)
    }

    return true
  }

  func userDidLogout() {
    AFOAuthCredential.deleteCredentialWithIdentifier(APICredentialID)
    UserFields.currentUser = nil

    window!.rootViewController = (storyboard.instantiateInitialViewController() as UIViewController)
  }
}