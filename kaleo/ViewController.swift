//
//  ViewController.swift
//  kaleo
//
//  Created by Chuong Le on 3/20/17.
//  Copyright © 2017 Poetic Systems. All rights reserved.
//


import UIKit
import AVFoundation
import PushKit
import CallKit
import TwilioVoiceClient

let baseURLString = "https://260e2e6b.ngrok.io"
let accessTokenEndpoint = "/access-token"

class ViewController: UIViewController, PKPushRegistryDelegate, TVONotificationDelegate, TVOCallDelegate, CXProviderDelegate {
    
    @IBOutlet weak var placeCallButton: UIButton!
    @IBOutlet weak var iconView: UIImageView!
    
    // Get Device info
    var device_uuid:String?
    
    var deviceTokenString:String?
    
    var voipRegistry:PKPushRegistry
    
    var isSpinning: Bool
    var incomingAlertController: UIAlertController?
    
    var callInvite:TVOCallInvite?
    var call:TVOCall?
    
    let callKitProvider:CXProvider
    let callKitCallController:CXCallController
    
    required init?(coder aDecoder: NSCoder) {
        
        device_uuid = UIDevice.current.identifierForVendor?.uuidString
        
        isSpinning = false
        // register push notification using PushKit
        voipRegistry = PKPushRegistry.init(queue: DispatchQueue.main)
        
        // The VoiceClient is the entry point for interaction with the Twilio service.
        // sharedInstance return the shared instance of the VoiceClient
        // set logging level of SDK
        VoiceClient.sharedInstance().logLevel = .verbose
        
        // A CXProvider​Configuration object controls the native call UI for incoming and outgoing calls,
        // including a localized name for the provider, the ringtone to be played for incoming calls,
        // and the icon to be displayed during calls.
        // A provider configuration can also set the maximum number of call groups and number of calls in a single call group,
        // determine whether to use emails and/or phone numbers as handles, and specify whether video is supported.
        let configuration = CXProviderConfiguration(localizedName: "Kaleo")
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        if let callKitIcon = UIImage(named: "iconMask80") {
            configuration.iconTemplateImageData = UIImagePNGRepresentation(callKitIcon)
        }
        
        // A CXProvider object is responsible for reporting out-of-band notifications that occur to the system.
        // A VoIP app should create only one instance of CXProvider and store it for use globally.
        callKitProvider = CXProvider(configuration: configuration)
        
        // A CXCall​Controller object interacts with calls by performing actions, which are represented by instances of CXCall​Action subclasses.
        callKitCallController = CXCallController()
        
        // http://stackoverflow.com/questions/24036393/fatal-error-use-of-unimplemented-initializer-initcoder-for-class
        super.init(coder: aDecoder)
        callKitProvider.setDelegate(self, queue: nil)
        
        voipRegistry.delegate = self
        voipRegistry.desiredPushTypes = Set([PKPushType.voIP])
    }
    
    // override func viewDidLoad() {
    //     super.viewDidLoad()
    
    //     // toggleUIState(isEnabled: true)
    // }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    // fetching access token via Twilio Rest API
    func fetchAccessToken() -> String? {
        // https://ericcerney.com/swift-guard-statement/
        
//        guard let accessTokenURL = URL(string: baseURLString + accessTokenEndpoint + "?device_uuid=" + device_uuid!) else {
//            return nil
//        }
        guard let accessTokenURL = URL(string: baseURLString + accessTokenEndpoint) else {
            return nil
        }
        
        // http://stackoverflow.com/questions/32390611/try-try-try-what-s-the-difference-and-when-to-use-each
        return try? String.init(contentsOf: accessTokenURL, encoding: .utf8)
    }
    
    // func toggleUIState(isEnabled: Bool) {
    //     placeCallButton.isEnabled = isEnabled
    // }
    
    // @IBAction func placeCall(_ sender: UIButton) {
    //     if (self.call != nil && self.call?.state == .connected) {
    //         self.call?.disconnect()
    //         self.toggleUIState(isEnabled: false)
    //     } else {
    //         let uuid = UUID()
    //         let handle = "Voice Bot"
    
    //         performStartCallAction(uuid: uuid, handle: handle)
    //     }
    // }
    
    
    // MARK: PKPushRegistryDelegate
    // A push registry delegate uses the methods of this protocol to react to token invalidation, push credential updates, and received remote pushes.
    // https://developer.apple.com/reference/pushkit/pkpushregistrydelegate
    
    // Notifies the delegate when the push credentials have been updated.
    func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, forType type: PKPushType) {
        NSLog("pushRegistry:didUpdatePushCredentials:forType:")
        
        if (type != .voIP) {
            return
        }
        
        guard let accessToken = fetchAccessToken() else {
            return
        }
        
        let deviceToken = (credentials.token as NSData).description
        
        VoiceClient.sharedInstance().register(withAccessToken: accessToken, deviceToken: deviceToken) { (error) in
            if (error != nil) {
                NSLog("An error occurred while registering: \(error?.localizedDescription)")
            }
            else {
                NSLog("Successfully registered for VoIP push notifications.")
            }
        }
        
        self.deviceTokenString = deviceToken
    }
    
    // Notifies the delegate that a push token has been invalidated.
    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenForType type: PKPushType) {
        NSLog("pushRegistry:didInvalidatePushTokenForType:")
        
        if (type != .voIP) {
            return
        }
        
        guard let deviceToken = deviceTokenString, let accessToken = fetchAccessToken() else {
            return
        }
        
        VoiceClient.sharedInstance().unregister(withAccessToken: accessToken, deviceToken: deviceToken) { (error) in
            if (error != nil) {
                NSLog("An error occurred while unregistering: \(error?.localizedDescription)")
            }
            else {
                NSLog("Successfully unregistered from VoIP push notifications.")
            }
        }
        
        self.deviceTokenString = nil
    }
    
    // Notifies the delegate that a remote push has been received
    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, forType type: PKPushType) {
        NSLog("pushRegistry:didReceiveIncomingPushWithPayload:forType:")
        
        if (type == PKPushType.voIP) {
            VoiceClient.sharedInstance().handleNotification(payload.dictionaryPayload, delegate: self)
        }
    }
    
    //http://stackoverflow.com/questions/5325226/what-is-the-difference-between-delegate-and-notification
    
    // MARK: TVONotificaitonDelegate
    
    // Notifies the delegate that an incoming call invite has been received. This comes from Twilio TVONotificaitonDelegate.
    func callInviteReceived(_ callInvite: TVOCallInvite) {
        NSLog("callInviteReceived:")
        
        if (self.callInvite != nil && self.callInvite?.state == .pending) {
            NSLog("Already a pending incoming call invite.");
            NSLog("  >> Ignoring call from %@", callInvite.from);
            return;
        } else if (self.call != nil) {
            NSLog("Already an active call.");
            NSLog("  >> Ignoring call from %@", callInvite.from);
            return;
        }
        
        self.callInvite = callInvite
        
        reportIncomingCall(from: callInvite.from, uuid: callInvite.uuid)
    }
    
    func callInviteCancelled(_ callInvite: TVOCallInvite?) {
        NSLog("callInviteCancelled:")
        
        if let callInvite = callInvite {
            performEndCallAction(uuid: callInvite.uuid)
        }
        
        self.callInvite = nil
    }
    
    func notificationError(_ error: Error) {
        NSLog("notificationError: \(error.localizedDescription)")
    }
    
    
    // MARK: TVOCallDelegate
    func callDidConnect(_ call: TVOCall) {
        NSLog("callDidConnect:")
        
        self.call = call
        
        // self.placeCallButton.setTitle("Hang Up", for: .normal)
        
        // toggleUIState(isEnabled: true)
        // stopSpin()
        // routeAudioToSpeaker()
    }
    
    func callDidDisconnect(_ call: TVOCall) {
        NSLog("callDidDisconnect:")
        
        performEndCallAction(uuid: call.uuid)
        
        self.call = nil
        
//        self.placeCallButton.setTitle("Place Outgoing Call", for: .normal)
        
//        toggleUIState(isEnabled: true)
    }
    
    func call(_ call: TVOCall, didFailWithError error: Error) {
        NSLog("call:didFailWithError: \(error.localizedDescription)")
        
        performEndCallAction(uuid: call.uuid)
        
        self.call = nil
//        toggleUIState(isEnabled: true)
//        stopSpin()
    }
    
    
    // MARK: AVAudioSession
    // func routeAudioToSpeaker() {
    //     do {
    //         try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayAndRecord, with: .defaultToSpeaker)
    //     } catch {
    //         NSLog(error.localizedDescription)
    //     }
    // }
    
    
    // MARK: Icon spinning
    // func startSpin() {
    //     if (isSpinning != true) {
    //         isSpinning = true
    //         spin(options: UIViewAnimationOptions.curveEaseIn)
    //     }
    // }
    
    // func stopSpin() {
    //     isSpinning = false
    // }
    
    // func spin(options: UIViewAnimationOptions) {
    //     UIView.animate(withDuration: 0.5,
    //                    delay: 0.0,
    //                    options: options,
    //                    animations: { [weak iconView] in
    //                     if let iconView = iconView {
    //                         iconView.transform = iconView.transform.rotated(by: CGFloat(M_PI/2))
    //                     }
    //     }) { [weak self] (finished: Bool) in
    //         guard let strongSelf = self else {
    //             return
    //         }
    
    //         if (finished) {
    //             if (strongSelf.isSpinning) {
    //                 strongSelf.spin(options: UIViewAnimationOptions.curveLinear)
    //             } else if (options != UIViewAnimationOptions.curveEaseOut) {
    //                 strongSelf.spin(options: UIViewAnimationOptions.curveEaseOut)
    //             }
    //         }
    //     }
    // }
    
    
    // MARK: CXProviderDelegate
    func providerDidReset(_ provider: CXProvider) {
        NSLog("providerDidReset:")
    }
    
    func providerDidBegin(_ provider: CXProvider) {
        NSLog("providerDidBegin")
    }
    
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        NSLog("provider:didActivateAudioSession:")
        
        VoiceClient.sharedInstance().startAudioDevice()
    }
    
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        NSLog("provider:didDeactivateAudioSession:")
    }
    
    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        NSLog("provider:timedOutPerformingAction:")
    }
    
    // func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    //     NSLog("provider:performStartCallAction:")
    
    //     guard let accessToken = fetchAccessToken() else {
    //         action.fail()
    //         return
    //     }
    
    //     VoiceClient.sharedInstance().configureAudioSession()
    
    //     call = VoiceClient.sharedInstance().call(accessToken, params: [:], delegate: self)
    
    //     guard let call = call else {
    //         NSLog("Failed to start outgoing call")
    //         action.fail()
    //         return
    //     }
    
    //     call.uuid = action.callUUID
    
    //     toggleUIState(isEnabled: false)
    //     startSpin()
    
    //     action.fulfill(withDateStarted: Date())
    // }
    
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        NSLog("provider:performAnswerCallAction:")
        
        // RCP: Workaround from https://forums.developer.apple.com/message/169511 suggests configuring audio in the
        //      completion block of the `reportNewIncomingCallWithUUID:update:completion:` method instead of in
        //      `provider:performAnswerCallAction:` per the WWDC examples.
        // VoiceClient.sharedInstance().configureAudioSession()
        
        guard let call = self.callInvite?.accept(with: self) else {
            action.fail()
            return
        }
        
        self.callInvite = nil
        
        call.uuid = action.callUUID
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        NSLog("provider:performEndCallAction:")
        
        VoiceClient.sharedInstance().stopAudioDevice()
        
        if (self.callInvite != nil && self.callInvite?.state == .pending) {
            self.callInvite?.reject()
            self.callInvite = nil
        } else if (self.call != nil) {
            self.call?.disconnect()
        }
        
        action.fulfill()
    }
    
    // // MARK: Call Kit Actions
    // func performStartCallAction(uuid: UUID, handle: String) {
    //     let callHandle = CXHandle(type: .generic, value: handle)
    //     let startCallAction = CXStartCallAction(call: uuid, handle: callHandle)
    //     let transaction = CXTransaction(action: startCallAction)
    
    //     callKitCallController.request(transaction)  { error in
    //         if let error = error {
    //             NSLog("StartCallAction transaction request failed: \(error.localizedDescription)")
    //             return
    //         }
    
    //         NSLog("StartCallAction transaction request successful")
    
    //         let callUpdate = CXCallUpdate()
    //         callUpdate.remoteHandle = callHandle
    //         callUpdate.supportsDTMF = true
    //         callUpdate.supportsHolding = false
    //         callUpdate.supportsGrouping = false
    //         callUpdate.supportsUngrouping = false
    //         callUpdate.hasVideo = false
    
    //         self.callKitProvider.reportCall(with: uuid, updated: callUpdate)
    //     }
    // }
    
    func reportIncomingCall(from: String, uuid: UUID) {
        let callHandle = CXHandle(type: .generic, value: from)
        
        let callUpdate = CXCallUpdate()
        callUpdate.remoteHandle = callHandle
        callUpdate.supportsDTMF = true
        callUpdate.supportsHolding = false
        callUpdate.supportsGrouping = false
        callUpdate.supportsUngrouping = false
        callUpdate.hasVideo = false
        
        callKitProvider.reportNewIncomingCall(with: uuid, update: callUpdate) { error in
            if let error = error {
                NSLog("Failed to report incoming call successfully: \(error.localizedDescription).")
                return
            }
            
            NSLog("Incoming call successfully reported.")
            
            // RCP: Workaround per https://forums.developer.apple.com/message/169511
            VoiceClient.sharedInstance().configureAudioSession()
        }
    }
    
    func performEndCallAction(uuid: UUID) {
        
        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)
        
        callKitCallController.request(transaction) { error in
            if let error = error {
                NSLog("EndCallAction transaction request failed: \(error.localizedDescription).")
                return
            }
            
            NSLog("EndCallAction transaction request successful")
        }
    }
}

