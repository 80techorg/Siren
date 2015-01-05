//
//  Siren.swift
//  Siren
//
//  Created by Arthur Sabintsev on 1/3/15.
//  Copyright (c) 2015 Sabintsev iOS Projects. All rights reserved.
//

import Foundation
import UIKit

// MARK: Delegate
@objc protocol SirenDelegate {
    optional func sirenDidShowUpdateDialog()       // User presented with update dialog
    optional func sirenUserDidLaunchAppStore()     // User did click on button that launched App Store.app
    optional func sirenUserDidSkipVersion()        // User did click on button that skips version update
    optional func sirenUserDidCancel()             // User did click on button that cancels update dialog
}

// MARK: Enumerations
/**
    Type of alert to present
*/
public enum SirenAlertType
{
    case Force        // Forces user to update your app
    case Option       // (DEFAULT) Presents user with option to update app now or at next launch
    case Skip         // Presents User with option to update the app now, at next launch, or to skip this version all together
    case None         // Don't show the alert type , usefull for skipping Patch ,Minor, Major update
}

/**
    How often alert should be presented
*/

public enum SirenVersionCheckType : Int
{
    case Immediately = 0
    case Daily = 1
    case Weekly = 7
}

/**
    Internationalization
*/
public enum SirenLanguageType: String
{
    case Basque = "eu"
    case ChineseSimplified = "zh-Hans"
    case ChineseTraditional = "zh-Hant"
    case Danish = "da"
    case Dutch = "nl"
    case English = "en"
    case French = "fr"
    case Hebrew = "he"
    case German = "de"
    case Italian = "it"
    case Japanese = "ja"
    case Korean = "ko"
    case Portuguese = "pt"
    case Russian = "ru"
    case Slovenian = "sl"
    case Sweidsh = "sv"
    case Spanish = "es"
    case Turkish = "tr"
}

// MARK: Siren
public class Siren: NSObject
{
    // MARK: Constants
    // Class Constants (Public)
    let sirenDefaultSkippedVersion = "Siren User Decided To Skip Version Update"
    let sirenDefaultStoredVersionCheckDate = "Siren Stored Date From Last Version Check"
    let currentVersion = NSBundle.mainBundle().currentVersion()
    let bundlePath = NSBundle.mainBundle().pathForResource("Siren", ofType: "Bundle")
    
    // Class Variables (Public)
    var debugEnabled = false
    weak var delegate: SirenDelegate?
    var appID: String?
    var appName: String = (NSBundle.mainBundle().infoDictionary?[kCFBundleNameKey] as? String) ?? ""
    var countryCode: String?
    var forceLanguageLocalization: SirenLanguageType?
    
    lazy var alertType = SirenAlertType.Option
    lazy var majorUpdateAlertType = SirenAlertType.Option
    lazy var minorUpdateAlertType = SirenAlertType.Option
    lazy var patchUpdateAlertType = SirenAlertType.Option
    
    var presentingViewController: UIViewController?
    var alertControllerTintColor: UIColor?
    
    // Class Variables (Private)
    private var appData: [String : AnyObject]?
    private var lastVersionCheckPerformedOnDate: NSDate?
    private var currentAppStoreVersion: String?
    
    // MARK: Initialization
    public class var sharedInstance: Siren {
        struct Singleton {
            static let instance = Siren()
        }
        
        return Singleton.instance
    }
    
    override init() {
        lastVersionCheckPerformedOnDate = NSUserDefaults.standardUserDefaults().objectForKey(self.sirenDefaultStoredVersionCheckDate) as? NSDate;
    }
    
    // MARK: Check Version
    func checkVersion(checkType: SirenVersionCheckType) {

        if (appID == nil || presentingViewController == nil) {
            println("[Siren]: Please make sure that you have set 'appID' and 'presentingViewController' before calling checkVersion, checkVersionDaily, or checkVersionWeekly")
        } else {
            if checkType == .Immediately {
                performVersionCheck()
            } else {
                if let lastCheckDate = lastVersionCheckPerformedOnDate {
                    if daysSinceLastVersionCheckDate() >= checkType.rawValue {
                        performVersionCheck()
                    }
                } else {
                    performVersionCheck()
                }
            }
        }
    }
    
    func performVersionCheck() {
        
        let itunesURL = iTunesURLFromString()
        let request = NSMutableURLRequest(URL: itunesURL)
        request.HTTPMethod = "GET"
        let session = NSURLSession.sharedSession()
        let task = session.dataTaskWithRequest(request, completionHandler: { (data, response, error) -> Void in
            
            if data.length > 0 {
                self.appData = NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.AllowFragments, error: nil) as? [String : AnyObject]
                
                if self.debugEnabled {
                    println("[Siren] JSON Results: \(self.appData!)");
                }
                
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    
                    // Store version comparison date
                    self.lastVersionCheckPerformedOnDate = NSUserDefaults.standardUserDefaults().objectForKey(self.sirenDefaultStoredVersionCheckDate) as? NSDate
                    NSUserDefaults.standardUserDefaults().setObject(self.lastVersionCheckPerformedOnDate, forKey: self.sirenDefaultStoredVersionCheckDate)
                    NSUserDefaults.standardUserDefaults().synchronize()
                    
                    // Extract all versions that have been uploaded to the AppStore
                    if let data = self.appData {
                        self.currentAppStoreVersion = data["results"]?[0]["version"] as? String
                        if let currentAppStoreVersion = self.currentAppStoreVersion {
                            self.checkIfAppStoreVersionIsNewestVersion()
                        }
                    }
                })
            } else if self.debugEnabled {
                println("[Siren] Error Retrieving App Store Data: \(error)")
            }
        })
        task.resume()
    }
    
    // MARK: Helpers
    func iTunesURLFromString() -> NSURL {
        
        var storeURLString = "https://itunes.apple.com/lookup?id=\(appID!)"
        
        if let countryCode = self.countryCode {
            storeURLString += "&country=\(countryCode)"
        }
        
        if debugEnabled {
            println("[Siren] iTunes Lookup URL: \(storeURLString)");
        }
        
        return NSURL(string: storeURLString)!
    }
    
    func daysSinceLastVersionCheckDate() -> Int {
        let calendar = NSCalendar.currentCalendar()
        let components = calendar.components(.CalendarUnitDay, fromDate: lastVersionCheckPerformedOnDate!, toDate: NSDate(), options: nil)
        return components.day
    }
    
    func checkIfAppStoreVersionIsNewestVersion() {
        
        // Check if current installed version is the newest public version or newer (e.g., dev version)
        if let currentInstalledVersion = currentVersion {
            if (self.currentAppStoreVersion!.compare(currentInstalledVersion, options: .NumericSearch) == NSComparisonResult.OrderedAscending) {
                showAlertIfCurrentAppStoreVersionNotSkipped()
            }
        }
    }
    
    var useAlertController : Bool {
        return objc_getClass("UIAlertController") != nil
    }
    
    // MARK: Alert
    func showAlertIfCurrentAppStoreVersionNotSkipped() {
        
        if let previouslySkippedVersion = NSUserDefaults.standardUserDefaults().objectForKey(sirenDefaultSkippedVersion) as? String {
            if currentAppStoreVersion! != previouslySkippedVersion {
                showAlert()
            }
        }
    }
    
    func showAlert() {
        // Show the alert
        if useAlertController {
//            let updateAvailableMessage = SirenLocalizedAlert().localizedString(SirenLocalizedAlertString.updateAvailableMessage, forcedLocalization: self.forceLanguageLocalization)
            
//            let alertController = UIAlertController(title: updateAvailableMessage, message: newVersionMessage, preferredStyle: .Alert)
            
//            if let alertControllerTintColor = alertControllerTintColor {
//                alertController.view.tintColor = alertControllerTintColor
//            }
            
            switch self.alertType {
                case .Force:
                    println("Force")
                case .Option:
                    println("Option")
                case .Skip:
                    println("Skip")
                case .None:
                    println("None")
            }
            
        }
    }
    
//    var alertType : SirenAlertType {
//        
//        var alertType = SirenAlertType.Option
//
//        // Set alert type for current version. Strings that don't represent numbers are treated as 0.
//        let oldVersion = split(currentVersion!, {$0 == "."}, maxSplit: Int.max, allowEmptySlices: false).map {$0.toInt() ?? 0}
//        let newVersion = split(currentVersion!, {$0 == "."}, maxSplit: Int.max, allowEmptySlices: false).map {$0.toInt() ?? 0}
//        
//        if oldVersion.count == 3 && newVersion.count == 3 {
//            if newVersion[0] > oldVersion[0] {
//                alertType = majorUpdateAlertType
//            } else if newVersion[1] > oldVersion[1] {
//                alertType = minorUpdateAlertType
//            } else if newVersion[2] > oldVersion[2] {
//                alertType = patchUpdateAlertType
//            }
//        }
//        
//        return alertType
//    }
}

// MARK: SirenLocalizedAlert

/**
Localization of Alert Strings
*/
private class SirenLocalizedAlertController: UIAlertController
{
    // TODO: Change these to 'class let' and remove Singleton when class level variables are supported
    let updateAvailableMessage = "Update Available"
    let newVersionMessage = "A new version of %@ is available. Please update to version %@ now."
    let updateButtonText = "Update"
    let nextTimeButtonText = "Next time"
    let skipButtonText = "Skip this version"
    let forceLanguageLocalization: SirenLanguageType?
    
     class var sharedInstance: SirenLocalizedAlertController {
        struct Singleton {
            static let instance = SirenLocalizedAlertController()
        }
        
        return Singleton.instance
    }
    
    override init() {
        self.forceLanguageLocalization = Siren.sharedInstance.forceLanguageLocalization
        super.init()
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    class func xlocalizedString(stringKey: String, forcedLocalization: SirenLanguageType?) -> String? {
        return NSBundle.mainBundle().localizedString(stringKey, forceLanguageLocalization: forcedLocalization)
    }
}


// MARK: Extensions
extension NSBundle {
    
    func currentVersion() -> String? {
        return self.objectForInfoDictionaryKey("CFBundleShortVersionString") as? String
    }

    func sirenBundlePath() -> String {
        return self.pathForResource("Siren", ofType: ".bundle") as String!
    }

    func sirenForcedBundlePath(forceLanguageLocalization: SirenLanguageType) -> String {
        let path = sirenBundlePath()
        let name = forceLanguageLocalization.rawValue
        return NSBundle(path: path)!.pathForResource(name, ofType: "lproj")!
    }

    private func localizedString(stringKey: String, forceLanguageLocalization: SirenLanguageType?) -> String? {
        var path: String
        let table = "SirenLocalizable"
        if let forceLanguageLocalization = forceLanguageLocalization {
            path = sirenForcedBundlePath(forceLanguageLocalization)
        } else {
            path = sirenBundlePath()
        }
        
        return NSBundle(path: path)?.localizedStringForKey(stringKey, value: stringKey, table: table)
    }
    
}