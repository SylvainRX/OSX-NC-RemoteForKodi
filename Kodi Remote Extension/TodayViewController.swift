//
//  TodayViewController.swift
//  Kodi Remote Extension
//
//  Created by Sylvain Roux on 2018-10-07.
//  Copyright © 2018 Sylvain Roux. All rights reserved.
//

import Cocoa
import NotificationCenter
import SocketRocket


class TodayViewController: NSViewController, NCWidgetProviding, SRWebSocketDelegate {
    var socket: SRWebSocket?
    var hostAddress: String = ""
    var hostPort: String = ""
    var hostUsername: String = ""
    var hostPassword: String = ""
    var isConnected: Bool = false { didSet { self.enableControls(self.isConnected) } }
    var switchingItemInPlaylist = false
    var playerId = PlayerId.none
    var applicationVolume: Float = 0.0 { didSet { self.volumeSlider?.floatValue = self.applicationVolume } }
    var lastRequestDate: Date?
    var lastRequestString: String?
    var isHeartbeating: Bool = false
    var playerItemCurrentTime = PlayerItemTime(hours: 0, minutes: 0, seconds: 0) { didSet { self.updateUiProgressLabel() } }
    var playerItemTotalTime = PlayerItemTime(hours: 0, minutes: 0, seconds: 0) { didSet { self.updateUiProgressLabel() } }
    var playerItemCurrentTimePercentage: Float = 0.0  { didSet { self.updateUiProgressSlider() } }
    var playerSpeed: Int = 0  { didSet { self.togglePlayButton() } }
    var isPlayerOn: Bool = false { didSet { self.collapsePlaylistViewIfNeeded() ; self.enablePlayerControls(self.isPlayerOn) } }
    var isPlaying: Bool = false { didSet { self.togglePlayButton() } }
    var currentItemTitle: String?
    var currentItemPositionInPlaylist: Int = -1
    var keyboardBehavior: KeyboardBehavior = .command
    var isEditingSettings: Bool = false
    var userDefaults: UserDefaults = UserDefaults.standard
    var isKeyEventMonitorSet: Bool = false
    
    
    var settingsView: SettingsView?
    @IBOutlet var volumeSlider: NSSlider?
    @IBOutlet var progressSlider: NSSlider?
    @IBOutlet var speedSlider: NSSlider?
    @IBOutlet var playerProgressLabel: NSTextField?
    @IBOutlet var volumeLabel: NSTextField?
    @IBOutlet var speedLabel: NSTextField?
    @IBOutlet var progressLabel: NSTextField?
    @IBOutlet var playlistPopUpButton: NSPopUpButtonCell?
    @IBOutlet var upButton: NSButton?
    @IBOutlet var downButton: NSButton?
    @IBOutlet var leftButton: NSButton?
    @IBOutlet var rightButton: NSButton?
    @IBOutlet var selectButton: NSButton?
    @IBOutlet var homeButton: NSButton?
    @IBOutlet var backButton: NSButton?
    @IBOutlet var infoButton: NSButton?
    @IBOutlet var menuButton: NSButton?
    @IBOutlet var stopButton: NSButton?
    @IBOutlet var nextButton: NSButton?
    @IBOutlet var playButton: NSButton?
    @IBOutlet var pauseButton: NSButton?
    @IBOutlet var inputTextField: NSTextField?
    @IBOutlet var navigationView: NSView?
    @IBOutlet var playView: NSView?
    @IBOutlet var sliderView: NSView?
    @IBOutlet var heightConstraint: NSLayoutConstraint?
    
    func widgetPerformUpdate(completionHandler: (@escaping (NCUpdateResult) -> Void)) {
        // Update your data and prepare for a snapshot. Call completion handler when you are done
        // with NoData if nothing has changed or NewData if there is new data since the last
        // time we called you
        completionHandler(.noData)
    }
    
    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        self.setKeyEventMonitorsIfNeeded()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder )
    }
    
    override func viewDidLoad() {
        self.fixDefaultsIfNeeded()
        self.connectToKodi()
        self.collapsePlaylistView(true)
    }
}

// MARK: Network
extension TodayViewController {
    func connectToKodi() {
        if self.socket != nil, self.socket!.readyState == SRReadyState.OPEN {
            self.socket!.close()
        }
        self.loadSettings()
        var stringURL: String
        if (self.hostUsername == "") {
            stringURL = "ws://\(self.hostAddress):\(self.hostPort)/jsonrpc"
        } else {
            stringURL = "ws://\(self.hostUsername):\(self.hostPassword)@\(self.hostAddress):\(self.hostPort)/jsonrpc"
        }
        if let anURL = URL(string: stringURL) {
            self.socket = SRWebSocket(urlRequest: URLRequest(url: anURL))
        }
        socket!.delegate = self
        Print.debug("Socket event : Atempting to connect to host at \(self.hostAddress):\(self.hostPort)")
        self.socket!.open()
    }
    
    func remoteRequest(_ request: String?, print: Bool = true) {
        if self.socket != nil {
            if self.socket!.readyState == SRReadyState.CLOSED {
                self.connectToKodi()
            } else if self.socket!.readyState == SRReadyState.OPEN {
                self.lastRequestDate = Date()
                self.lastRequestString = request ?? ""
                self.socket!.send(request)
                if print { Print.debugJson(request!) }
            }
        }
    }
    
    func webSocket(_ webSocket: SRWebSocket!, didFailWithError error: Error!) {
        self.isConnected = false
    }
    
    func webSocketDidOpen(_ webSocket: SRWebSocket!) {
        Print.debug("Connected to Kodi")
        self.playerHeartbeat()
        self.requestApplicationVolume()
        self.isConnected = true
    }
    
    func webSocket(_ webSocket: SRWebSocket?, didReceiveMessage message: Any!) {
        var data: [String: Any]?
        if let anEncoding = (message as! String).data(using: String.Encoding.utf8) {
            guard let jsonObject = try? JSONSerialization.jsonObject(with: anEncoding, options: []) as! [String: Any] else {
                Print.debug("Parsing error")
                return
            }
            if jsonObject["params"] != nil
                ,let params = (jsonObject["params"] as? [String: Any])
                ,let parsedData = params["data"] as? [String: Any]? {
                data = parsedData as [String: Any]? ?? [String: Any]()
            }
            else if jsonObject["result"] != nil
            {
                if let parsedData = jsonObject["result"] as? [[String: Any]]?, parsedData!.count != 0 {
                    data = parsedData![0] as [String: Any]? ?? [String: Any]()
                }
                else if let parsedData = jsonObject["result"] as? [String: Any]? {
                    data = parsedData as [String: Any]? ?? [String: Any]()
                }
            }
            
            var shouldPrint = true
            
            if let requestId = RequestId(rawValue: jsonObject["id"] as! Int? ?? 0) {
                shouldPrint = requestId != .playerPropertyPercentageSpeed && requestId != .playerGetActivePlayers
                switch requestId {
                case .playerPropertyPercentageSpeed:
                    self.handlePlayerGetPropertiesPercentageSpeed(data)
                    break
                case .applicationVolume:
                    self.handleApplicationVolume(data)
                    break
                case .playlistGetItems:
                    self.handlePlaylistGetItems(data)
                    break
                case .playerGetItem:
                    self.handlePlayerGetItem(data)
                    break
                case .playerGetActivePlayers:
                    self.handlePlayerGetActivePlayers(data)
                    break
                case .playerGetPropertyPlaylistPosition:
                    self.handlePlayerGetPropertiesPlaylistPosition(data)
                    break
                }
            }
            else if let notificationId = NotificationId(rawValue: jsonObject["method"] as! String? ?? "") {
                switch notificationId {
                case .applicationOnVolumeChanged:
                    self.handleApplicationVolume(data)
                    break
                case .playerOnPlay:
                    self.handlePlayerOnPlay(data)
                    break
                case .playerOnPause:
                    self.handlePlayerOnPause()
                    break
                case .playerOnStop:
                    self.handlePlayerOnStop()
                    break
                case .playlistOnAdd:
                    self.handlePlaylistOnAdd(data)
                    break
                case .inputOnInputRequested:
                    self.handleInputOnInputRequested()
                    break
                case .inputOnInputFinished:
                    self.handleInputOnInputFinished()
                }
            }
            if shouldPrint { Print.debugJson(message as! String) }
        }
    }
}

// MARK: Settings
extension TodayViewController {
    var widgetAllowsEditing: Bool { get { return true } }
    
    func fixDefaultsIfNeeded() {
        let domains = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true)
        //File should be in library
        let libraryPath = domains.first
        if libraryPath != nil {
            let preferensesPath = URL(fileURLWithPath: libraryPath ?? "").appendingPathComponent("Preferences").absoluteString
            //Defaults file name similar to bundle identifier
            let bundleIdentifier = Bundle.main.bundleIdentifier
            //Add correct extension
            let defaultsName = bundleIdentifier ?? "" + (".plist")
            let defaultsPath = URL(fileURLWithPath: preferensesPath).appendingPathComponent(defaultsName).absoluteString
            let manager = FileManager.default
            if !manager.fileExists(atPath: defaultsPath) {
                //Create to fix issues
                manager.createFile(atPath: defaultsPath, contents: nil, attributes: nil)
                //And restart defaults at the end
                UserDefaults.resetStandardUserDefaults()
                UserDefaults.standard.synchronize()
            }
        }
    }
    func saveSettings() {
        self.fixDefaultsIfNeeded()
        self.userDefaults.set(self.settingsView?.addressTextField?.stringValue, forKey: "address")
        self.userDefaults.set(self.settingsView?.portTextField?.stringValue, forKey: "port")
        self.userDefaults.set(self.settingsView?.usernameTextField?.stringValue, forKey: "username")
        self.userDefaults.set(self.settingsView?.passwordTextField?.stringValue, forKey: "password")
        self.userDefaults.synchronize()
        self.hostAddress = (self.settingsView?.addressTextField!.stringValue)!
        self.hostPort = (self.settingsView?.portTextField!.stringValue)!
        self.hostUsername = (self.settingsView?.usernameTextField!.stringValue)!
        self.hostPassword = (self.settingsView?.passwordTextField!.stringValue)!
    }
    func loadSettings() {
        self.fixDefaultsIfNeeded()
        if let hostAddress = UserDefaults.standard.object(forKey: "address") {
            self.hostAddress = hostAddress as! String
        }
        if let hostPort = UserDefaults.standard.object(forKey: "port") {
            self.hostPort = hostPort as! String
        }
        if let hostUsername = UserDefaults.standard.object(forKey: "username") {
            self.hostUsername = hostUsername as! String
        }
        if let hostPassword = UserDefaults.standard.object(forKey: "password") {
            self.hostPassword = hostPassword as! String
        }
    }
    func setKeyEventMonitorsIfNeeded() {
        if !self.isKeyEventMonitorSet {
            self.isKeyEventMonitorSet = true
            NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [unowned self] (event) -> NSEvent? in
                self.keyUp(with: event)
                return event
            }
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [unowned self] (event) -> NSEvent? in
                self.keyDown(with: event)
                return event
            }
        }
    }}

// MARK: Requests to Kodi
extension TodayViewController {
    func sendInputDown() {
        //Input.Down
        let request = "{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.Down\"}"
        self.remoteRequest(request)
    }
    func sendInputLeft() {
        //Input.Left
        let request = "{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.Left\"}"
        self.remoteRequest(request)
    }
    func sendInputRight() {
        //Input.Right
        let request = "{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.Right\"}"
        self.remoteRequest(request)
    }
    func sendInputUp() {
        //Input.Up
        let request = "{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.Up\"}"
        self.remoteRequest(request)
    }
    func sendInputSelect() {
        //Input.Select
        let request = "{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.Select\"}"
        self.remoteRequest(request)
    }
    func sendInputExecuteActionBack() {
        //Input.ExecuteAction back
        let request = "{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.ExecuteAction\",\"params\":{\"action\":\"back\"}}"
        self.remoteRequest(request)
    }
    func sendInputExecuteActionContextMenu() {
        //Input.ExecuteAction contextmenu
        //Input.ShowOSD
        var request = "{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.ExecuteAction\",\"params\":{\"action\":\"contextmenu\"},\"id\":0}"
        self.remoteRequest(request)
        request = "{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.ShowOSD\"}"
        self.remoteRequest(request)
    }
    func sendInputInfo() {
        //Input.Info
        let request = "{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.Info\"}"
        self.remoteRequest(request)
    }
    func sendInputHome() {
        //Input.Home
        let request = "{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.Home\"}"
        remoteRequest(request)
    }
    func sendInputExecuteActionPause() {
        //Input.ExecuteAction pause
        let request = "{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.ExecuteAction\",\"params\":{\"action\":\"pause\"}}"
        self.remoteRequest(request)
    }
    func sendInputExecuteActionStop() {
        //Input.ExecuteAction stop
        let request = "{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.ExecuteAction\",\"params\":{\"action\":\"stop\"}}"
        self.remoteRequest(request)
    }
    func sendApplicationSetVolume(_ volume: Int) {
        //Application.SetVolume
        let request = String(format: "{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Application.SetVolume\",\"params\":{\"volume\":%i}}", volume)
        self.remoteRequest(request)
    }
    func sendApplicationSetVolumeIncrement() {
        //Application.SetVolume applicationVolume+5
        let request = String(format: "{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Application.SetVolume\",\"params\":{\"volume\":%i}}", Int(applicationVolume) + 5)
        self.remoteRequest(request)
    }
    func sendApplicationSetVolumeDecrement() {
        //Application.SetVolume self.applicationVolume-5
        let request = String(format: "{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Application.SetVolume\",\"params\":{\"volume\":%i}}", Int(applicationVolume) - 5)
        self.remoteRequest(request)
    }
    func sendPlayerOpenVideo() {
        //Player.Open
        let request = "{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Player.Open\",\"params\":{\"item\":{\"playlistid\":1}}}"
        self.remoteRequest(request)
    }
    func sendPlaylistAddVideoStreamLink(_ link: String?) {
        //Playlist.Add
        let request = "{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Playlist.Add\",\"params\":{\"playlistid\":1, \"item\":{\"file\":\"\(link ?? "")\"}}}"
        self.remoteRequest(request)
    }
    func sendPlaylistClearVideo() {
        //Playlist.Clear
        let request = "{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Playlist.Clear\",\"params\":{\"playlistid\":1}}"
        self.remoteRequest(request)
    }
    func sendPlayerSeek(_ percentage: Int) {
        //Player.Seek
        let request = String(format: "{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Player.Seek\",\"params\":{\"playerid\":%ld,\"value\":%i}}", self.playerId.rawValue, percentage)
        self.remoteRequest(request)
    }
    func sendPlayerSeekForward() {
        //Player.Seek
        let request = String(format: "{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Player.Seek\",\"params\":{\"playerid\":%ld,\"value\":\"smallforward\"}}", self.playerId.rawValue)
        self.remoteRequest(request)
    }
    func sendPlayerSeekBackward() {
        //Player.Seek
        let request = String(format: "{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Player.Seek\",\"params\":{\"playerid\":%ld,\"value\":\"smallbackward\"}}", self.playerId.rawValue)
        self.remoteRequest(request)
    }
    func sendPlayerSetSpeed(_ speed: Int) {
        //Player.SetSpeed
        var lc_speed: Int
        if speed == 0 {
            lc_speed = 0
        } else {
            lc_speed = Int(truncating: NSDecimalNumber(decimal: (pow(2, abs(speed))))) * (speed / abs(speed)) //[1]=2 [2]=4 [3]=8 [4]=16 [5]=32
        }
        let request = String(format: "{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Player.SetSpeed\",\"params\":{\"playerid\":%ld,\"speed\":%i}}", self.playerId.rawValue, lc_speed)
        self.remoteRequest(request)
    }
    func sendPlayerGoToPrevious() {
        //Player.GoTo
        let request = String(format: "{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Player.GoTo\",\"params\":{\"playerid\":%ld,\"to\":\"previous\"}}", self.playerId.rawValue)
        self.remoteRequest(request)
    }
    func sendPlayerGoToNext() {
        //Player.GoTo
        //        if self.switchingItemInPlaylist {
        //            return
        //        }
        switchingItemInPlaylist = true
        currentItemPositionInPlaylist += 1
        let request = String(format: "{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Player.GoTo\",\"params\":{\"playerid\":%ld,\"to\":\"next\"}}", self.playerId.rawValue)
        self.remoteRequest(request)
    }
    func sendPlayerGoPlaylistItem(atIndex index: Int) {
        //Player.GoTo
        if switchingItemInPlaylist {
            return
        }
        switchingItemInPlaylist = true
        if currentItemPositionInPlaylist == index {
            switchingItemInPlaylist = false
            return
        }
//        currentItemPositionInPlaylist = index
        let request = String(format: "{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Player.GoTo\",\"params\":{\"playerid\":%ld,\"to\":%d}}", self.playerId.rawValue, index)
        self.remoteRequest(request)
    }
    func sendSystemReboot() {
        //System.Reboot
        let request = "{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"System.Reboot\"}"
        self.remoteRequest(request)
    }
    func sendVideoLibraryScan() {
        //VideoLibrary.Scan
        let request = "{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"VideoLibrary.Scan\"}"
        self.remoteRequest(request)
    }
    func sendInputSendText(_ string: String?, andSubmit submit: Bool) {
        //Input.SendText
        var done: String
        let safeString = string?.replacingOccurrences(of: "\"", with: "\\\"")
        if submit {
            done = "true"
        } else {
            done = "false"
        }
        let request = "{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.SendText\",\"params\":{\"text\":\"\(safeString ?? "")\",\"done\":\(done)}}"
        self.remoteRequest(request)
    }
    func requestApplicationVolume() {
        //Application.GetProperties
        let request = "{\"id\":2,\"jsonrpc\":\"2.0\",\"method\":\"Application.GetProperties\",\"params\":{\"properties\":[\"volume\"]}}"
        self.remoteRequest(request)
    }
    func requestPlayerGetPropertiesPercentageSpeed() {
        //Player.GetProperties
        if self.playerId == .none {
            return
        }
        let request = String(format: "{\"id\":1,\"jsonrpc\":\"2.0\",\"method\":\"Player.GetProperties\",\"params\":{\"playerid\":%ld,\"properties\":[\"time\",\"totaltime\",\"percentage\",\"speed\"]}}", self.playerId.rawValue)
        self.remoteRequest(request, print: false)
    }
    func requestPlayerGetPropertiesPlaylistPosition() {
        //Player.GetProperties
        if self.playerId == .none {
            return
        }
        let request = String(format: "{\"id\":6,\"jsonrpc\":\"2.0\",\"method\":\"Player.GetProperties\",\"params\":{\"playerid\":%ld,\"properties\":[\"position\"]}}", self.playerId.rawValue)
        self.remoteRequest(request)
    }
    func requestPlayerGetItem() {
        //Player.GetItem
        let request = String(format: "{\"id\":4,\"jsonrpc\":\"2.0\",\"method\":\"Player.GetItem\",\"params\":{\"playerid\":%ld}}", self.playerId.rawValue)
        self.remoteRequest(request)
    }
    func requestPlaylistGetItems() {
        //Playlist.GetItems
        let request = String(format: "{\"id\":3,\"jsonrpc\":\"2.0\",\"method\":\"Playlist.GetItems\",\"params\":{\"playlistid\":%ld}}", self.playerId.rawValue)
        self.remoteRequest(request)
    }
    func requestPlayerGetActivePlayers() {
        //Player.GetActivePlayers
        let request = "{\"id\":5,\"jsonrpc\":\"2.0\",\"method\":\"Player.GetActivePlayers\"}"
        self.remoteRequest(request, print: false)
    }
    func sendStreamLink(_ link: String?) {
        if let link = link {
            var plugginSpecificCommand: String?
            if link.contains("youtube.com/") {
                if let videoArgPos = link.range(of: "v=") {
                    let videoArgEnd = link.index(videoArgPos.upperBound, offsetBy: 11)
                    let videoId = String(link[videoArgPos.upperBound..<videoArgEnd])
                    plugginSpecificCommand = "plugin://plugin.video.youtube/?action=play_video&videoid=\(videoId)"
                }
            }
            else if link.contains("vimeo.com/") {
                let videoId = link.suffix(9)
                plugginSpecificCommand = "plugin://plugin.video.vimeo/play/?video_id=\(videoId)"
            }
            else if link.contains("dailymotion.com/") {
                if let videoArgPos = link.range(of: "/", options: .backwards) {
                    let videoId = String(link[videoArgPos.upperBound..<link.endIndex])
                    plugginSpecificCommand = "plugin://plugin.video.dailymotion/?action=play_video&videoid=\(videoId)"
                }
            }
            if plugginSpecificCommand != nil {
                if self.playerId != .video {
                    sendPlaylistClearVideo()
                    sendPlaylistAddVideoStreamLink(plugginSpecificCommand)
                    sendPlayerOpenVideo()
                } else {
                    sendPlaylistAddVideoStreamLink(plugginSpecificCommand)
                }
            }
        }
    }
}


// MARK: Response handlers
extension TodayViewController {
    func handleApplicationVolume(_ params: [String: Any]?) {
        // Response to Application.GetProperties
        if let params = params, let volume = params["volume"] as? NSNumber {
            self.applicationVolume = volume.floatValue
        }
    }
    func handlePlayerGetPropertiesPercentageSpeed(_ params: [String: Any]?) {
        //Response to Player.GetProperties Percentage Speed
        if let params = params {
            let time = params["time"] as! [String: Any]
            self.playerItemCurrentTime = PlayerItemTime(hours: time["hours"] as! Int,
                                                        minutes: time["minutes"] as! Int,
                                                        seconds: time["seconds"] as! Int)
            let totalTime = params["totaltime"] as! [String: Any]
            self.playerItemTotalTime = PlayerItemTime(hours: totalTime["hours"] as! Int,
                                                      minutes: totalTime["minutes"] as! Int,
                                                      seconds: totalTime["seconds"] as! Int)
            self.playerItemCurrentTimePercentage = (params["percentage"] as! NSNumber).floatValue
            self.playerSpeed = params["speed"] as! Int
            self.isPlaying = self.playerSpeed != 0
        }
    }
    func handlePlayerGetPropertiesPlaylistPosition(_ params: [String: Any]?) {
        if let params = params {
            self.currentItemPositionInPlaylist = params["position"] as! Int
            self.playlistPopUpButton?.selectItem(at: self.currentItemPositionInPlaylist)
            self.requestPlayerGetItem()
        }
    }
    func handlePlayerGetItem(_ params: [String: Any]?) {
        if let params = params {
            let item = params["item"] as? [String: Any]
            let itemLabel = item!["label"] as? String
            let title = itemLabel ?? ""
            self.setTitle(title, forItemAtIndex: self.currentItemPositionInPlaylist, updateTitle: true)
            self.playlistPopUpButton?.selectItem(at: self.currentItemPositionInPlaylist)
            self.collapsePlaylistViewIfNeeded()
        }
    }
    func handlePlayerGetActivePlayers(_ params: [String: Any]?) {
        if let params = params {
            if params.count == 0 {
                self.playerId = .none
                self.isPlayerOn = false
            } else {
                let oldPlayerId = self.playerId
                self.playerId = PlayerId(rawValue: params["playerid"] as! Int) ?? .none
                self.isPlayerOn = true
                if self.playerId != oldPlayerId {
                    self.requestPlaylistGetItems()
                }
            }
        }
    }
    func handlePlayerOnPlay(_ params: [String: Any]?) {
        if let params = params {
            self.isPlayerOn = true
            self.isPlaying = true
            switchingItemInPlaylist = false
            let item = params["item"] as? [String: Any]
            let itemLabel = item!["label"] as? String
            let title = itemLabel ?? ""
            self.currentItemTitle = title
            self.requestPlayerGetPropertiesPlaylistPosition()
            self.collapsePlaylistViewIfNeeded()
        }
    }
    func handlePlayerOnPause() {
        self.isPlaying = false
    }
    func handlePlayerOnStop() {
        self.isPlayerOn = false
        self.isPlaying = false
        self.currentItemPositionInPlaylist = -1
        self.playlistPopUpButton?.removeAllItems()
        self.collapsePlaylistView(true)
    }
    func handlePlaylistGetItems(_ params: [String: Any]?) {
        if let params = params {
            let jsonPlaylistItems = params["items"] as? [[String: Any]] ?? []
            self.playlistPopUpButton?.removeAllItems()
            for (index, jsonPlaylistItem) in jsonPlaylistItems.enumerated() {
                let itemLabel = jsonPlaylistItem["label"] as? String ?? ""
                self.setTitle(itemLabel, forItemAtIndex: index)
            }
            //Update object
            self.requestPlayerGetPropertiesPlaylistPosition()
        }
    }
    func handlePlaylistOnAdd(_ params: [String: Any]?) {
        if let params = params {
            let item = params["item"] as! [String: Any]
            let itemTitle = item["title"] as? String
            let position = params["position"] as! Int
            self.setTitle(itemTitle ?? "", forItemAtIndex: position)
        }
    }
    func handleInputOnInputRequested() {
        self.enableInputTextField(true)
    }
    func handleInputOnInputFinished() {
        self.enableInputTextField(false)
    }
}


// MARK: Application Inputs
extension TodayViewController {
    @IBAction func up(sender: NSButton) { self.sendInputUp() ; sender.isHighlighted = false }
    @IBAction func down(sender: NSButton) { self.sendInputDown() ; sender.isHighlighted = false  }
    @IBAction func left(sender: NSButton) { self.sendInputLeft() ; sender.isHighlighted = false  }
    @IBAction func right(sender: NSButton) { self.sendInputRight() ; sender.isHighlighted = false  }
    @IBAction func select(sender: NSButton) { self.sendInputSelect() ; sender.isHighlighted = false  }
    @IBAction func home(sender: NSButton) { self.sendInputHome() ; sender.isHighlighted = false  }
    @IBAction func back(sender: NSButton) { self.sendInputExecuteActionBack() ; sender.isHighlighted = false  }
    @IBAction func info(sender: NSButton) { self.sendInputInfo() ; sender.isHighlighted = false  }
    @IBAction func menu(sender: NSButton) { self.sendInputExecuteActionContextMenu() ; sender.isHighlighted = false  }
    @IBAction func stop(sender: NSButton) { self.sendInputExecuteActionStop() ; sender.isHighlighted = false }
    @IBAction func next(sender: NSButton) { self.sendPlayerGoToNext() ; sender.isHighlighted = false  }
    @IBAction func togglePause(sender: NSButton) { self.sendInputExecuteActionPause() ; self.playButton!.isHighlighted = false ; self.pauseButton!.isHighlighted = false }
    @IBAction func volume(slider: NSSlider) { self.sendApplicationSetVolume(Int(slider.intValue)) }
    @IBAction func speed(slider: NSSlider) {
        let event: NSEvent? = NSApplication.shared.currentEvent
        if event?.type == .leftMouseUp {
            slider.doubleValue = 0.0
        }
        self.sendPlayerSetSpeed(Int(slider.intValue))
    }
    @IBAction func progress(slider: NSSlider) { self.sendPlayerSeek(slider.integerValue) }
    @IBAction func playlistSelect(playlistPopUpButton: NSPopUpButtonCell) {
        self.sendPlayerGoPlaylistItem(atIndex: playlistPopUpButton.indexOfSelectedItem)
    }
    
    override func keyDown(with event: NSEvent) {
        if self.keyboardBehavior == .command, !self.isEditingSettings {
            if let keyboardKey = KeyboardKey(rawValue: event.keyCode) {
                switch keyboardKey {
                case .s: self.stopButton?.highlight(true) ; break
                case .h: self.homeButton?.highlight(true) ; break
                case .x: self.stopButton?.highlight(true) ; break
                case .c: self.menuButton?.highlight(true) ; break
                case .i: self.infoButton?.highlight(true) ; break
                case .ret: self.selectButton?.highlight(true) ; break
                case .n: self.nextButton?.highlight(true) ; break
                case .m: self.menuButton?.highlight(true) ; break
                case .tab: self.highlightNavigation(true) ; break
                case .space: self.playButton?.highlight(true) ; self.pauseButton?.highlight(true) ; break
                case .back: self.backButton?.highlight(true) ; break
                case .left: self.leftButton?.highlight(true) ; break
                case .right: self.rightButton?.highlight(true) ; break
                case .down: self.downButton?.highlight(true) ; break
                case .up: self.upButton?.highlight(true) ; break
                default: break
                }
            }
        }
    }
    override func keyUp(with event: NSEvent) {
        if !self.isEditingSettings {
            switch self.keyboardBehavior {
            case .command:
                self.keyBoardCommand(with: event)
                break
            case .textInput:
                self.textInput(with: event)
                break
            }
        }
    }
    func keyBoardCommand(with event: NSEvent) {
        if let keyboardKey = KeyboardKey(rawValue: event.keyCode) {
            switch keyboardKey {
            case .s:
                self.stop(sender: self.stopButton!) ; break
            case .f:
                self.sendPlayerSeekForward() ; break
            case .h:
                self.home(sender: self.homeButton!) ; break
            case .x:
                self.stop(sender: self.stopButton!) ; break
            case .c:
                self.menu(sender: self.menuButton!) ; break
            case .v:
                if event.modifierFlags.contains(.command) { self.sendStreamLink(NSPasteboard.general.string(forType: .string))} ; break
            case .b:
                self.sendPlayerSeekBackward() ; break
            case .r:
                if event.modifierFlags.contains(.command) { self.sendSystemReboot() } ; break
            case .u:
                self.sendVideoLibraryScan() ; break
            case .i:
                self.info(sender: self.infoButton!) ; break
            case .p:
                self.sendPlayerGoToPrevious() ; break
            case .ret:
                self.select(sender: self.selectButton!) ; break
            case .n:
                self.next(sender: self.nextButton!) ; break
            case .m:
                self.menu(sender: self.menuButton!) ; break
            case .tab:
                self.highlightNavigation(false) ; break
            case .space:
                self.togglePause(sender: self.playButton!) ; break
            case .back:
                self.back(sender: self.backButton!) ; break
            case .left:
                if event.modifierFlags.contains(.shift) { self.sendPlayerSeekBackward() ; self.leftButton?.isHighlighted = false }
                else { self.left(sender: self.leftButton!) } ; break
            case .right:
                if event.modifierFlags.contains(.shift) { self.sendPlayerSeekForward() ; self.rightButton?.isHighlighted = false }
                else { self.right(sender: self.rightButton!) } ; break
            case .down:
                if event.modifierFlags.contains(.shift) { self.sendApplicationSetVolumeDecrement() ; self.downButton?.isHighlighted = false }
                else { self.down(sender: self.downButton!) } ; break
            case .up:
                if event.modifierFlags.contains(.shift) { self.sendApplicationSetVolumeIncrement() ; self.upButton?.isHighlighted = false }
                else { self.up(sender: self.upButton!) } ; break
            default: break
            }
        }
    }
    func textInput(with event: NSEvent) {
        let string = self.inputTextField?.stringValue
        if let keyboardKey = KeyboardKey(rawValue: event.keyCode) {
            switch keyboardKey {
            case .ret:
                self.sendInputSendText(string, andSubmit: true)
            case .back:
                if string?.count == 0 {
                    self.sendInputExecuteActionBack()
                }
            case .escape:
                self.sendInputExecuteActionBack()
            default:
                self.sendInputSendText(string, andSubmit: false)
                break
            }
        }
    }
    
    @objc func playerHeartbeat() {
        requestPlayerGetPropertiesPercentageSpeed()
        requestPlayerGetActivePlayers()
        Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(self.playerHeartbeat), userInfo: nil, repeats: false)
    }
}


// MARK: UI Updates
extension TodayViewController {
    func togglePlayButton() {
        self.playButton?.isHidden = self.isPlaying
        self.pauseButton?.isHidden = !self.isPlaying
    }
    func updateUiProgressLabel() {
        let currentTimeString = String(format: "%2d", self.playerItemCurrentTime.hours)
            + ":" + String(format: "%02d", self.playerItemCurrentTime.minutes)
            + ":" + String(format: "%02d", self.playerItemCurrentTime.seconds)
        let totalTimeString = String(format: "%d", self.playerItemTotalTime.hours)
            + ":" + String(format: "%02d", self.playerItemTotalTime.minutes)
            + ":" + String(format: "%02d", self.playerItemTotalTime.seconds)
        self.playerProgressLabel?.stringValue = currentTimeString + "/" + totalTimeString
    }
    func updateUiProgressSlider() {
        self.progressSlider?.floatValue = self.playerItemCurrentTimePercentage
    }
    func setTitle(_ title: String, forItemAtIndex itemIndex: Int, updateTitle: Bool = false) {
        if itemIndex != -1 {
            var duplicateNumber = 1
            if self.playlistPopUpButton?.numberOfItems ?? 0 > itemIndex {
                if updateTitle {
                    self.playlistPopUpButton?.removeItem(at: itemIndex)
                }
                self.playlistPopUpButton?.insertItem(withTitle: title, at: itemIndex)
            }
            else {
                var uniqueTitle = title
                while (self.playlistPopUpButton?.item(withTitle: uniqueTitle)) != nil {
                    uniqueTitle = "\(title) (\(duplicateNumber))"
                    duplicateNumber += 1
                }
                self.playlistPopUpButton?.addItem(withTitle: uniqueTitle)
            }
        }
    }
    func enableInputTextField(_ enabled: Bool) {
        self.upButton?.isEnabled = !enabled
        self.downButton?.isEnabled = !enabled
        self.leftButton?.isEnabled = !enabled
        self.rightButton?.isEnabled = !enabled
        self.inputTextField?.isHidden = !enabled
        self.playView?.isHidden = enabled
        self.sliderView?.isHidden = enabled
        self.view.window?.makeFirstResponder(self.inputTextField)
        self.keyboardBehavior = enabled ? .textInput : .command
    }
    func collapsePlaylistViewIfNeeded() {
        self.collapsePlaylistView(self.playlistPopUpButton?.itemTitles.count ?? 0 <= 1 || self.isEditingSettings)
    }
    func collapsePlaylistView(_ collapse: Bool) {
        let height: CGFloat = collapse ? 87 : 115
        self.preferredContentSize = NSSize(width: self.preferredContentSize.width, height: height)
    }
    func enableControls(_ enable: Bool) {
        self.enablePlayerControls(enable && self.isPlaying)
        self.volumeSlider?.isEnabled = enable
        self.homeButton?.isEnabled = enable
        self.menuButton?.isEnabled = enable
        self.infoButton?.isEnabled = enable
        self.backButton?.isEnabled = enable
        self.upButton?.isEnabled = enable
        self.downButton?.isEnabled = enable
        self.leftButton?.isEnabled = enable
        self.rightButton?.isEnabled = enable
        self.selectButton?.isEnabled = enable
        self.volumeLabel?.alphaValue = enable ? 0.8 : 0.3
    }
    func enablePlayerControls(_ enable: Bool) {
        self.playButton?.isEnabled = enable
        self.pauseButton?.isEnabled = enable
        self.stopButton?.isEnabled = enable
        self.nextButton?.isEnabled = enable
        self.speedSlider?.isEnabled = enable
        self.progressSlider?.isEnabled = enable
        let labelAlpha: CGFloat = enable ? 0.8 : 0.3
        self.speedLabel?.alphaValue = labelAlpha
        self.progressLabel?.alphaValue = labelAlpha
        self.playerProgressLabel?.alphaValue = enable ? 0.65 : 0.2
        self.volumeLabel?.alphaValue = 0.8
    }
    func highlightNavigation(_ highlighted: Bool) {
        self.upButton!.isHighlighted = highlighted ; self.downButton!.isHighlighted = highlighted
        self.leftButton!.isHighlighted = highlighted ; self.rightButton!.isHighlighted = highlighted
        self.selectButton!.isHighlighted = highlighted
    }
    func toggleSettings() {
        self.isEditingSettings = !self.isEditingSettings
        if self.isEditingSettings {
            var topLevelObjects : NSArray?
            if Bundle.main.loadNibNamed("SettingsView", owner: self, topLevelObjects: &topLevelObjects) {
                if self.settingsView == nil {
                    self.settingsView = topLevelObjects!.first(where: { $0 is SettingsView }) as? SettingsView
                }
                self.settingsView!.frame = CGRect(x: 0, y: 0, width: self.view.frame.width, height: self.view.frame.height)
                self.collapsePlaylistViewIfNeeded()
                self.view.addSubview(self.settingsView!)
                self.settingsView!.addressTextField!.stringValue = self.hostAddress
                self.settingsView!.portTextField!.stringValue = self.hostPort
                self.settingsView!.usernameTextField!.stringValue = self.hostUsername
                self.settingsView!.passwordTextField!.stringValue = self.hostPassword
            }
        }
        else {
            self.settingsView?.removeFromSuperview()
        }
        self.enableInputTextField(false)
        self.navigationView?.isHidden = self.isEditingSettings
        self.sliderView?.isHidden = self.isEditingSettings
        self.playView?.isHidden = self.isEditingSettings
        self.collapsePlaylistViewIfNeeded()
    }
    func widgetDidBeginEditing() { self.loadSettings() ; toggleSettings() }
    func widgetDidEndEditing() { self.saveSettings() ; self.toggleSettings() ; self.connectToKodi()}
}


class SettingsView: NSView  {
    @IBOutlet var addressTextField: NSTextField?
    @IBOutlet var portTextField: NSTextField?
    @IBOutlet var usernameTextField: NSTextField?
    @IBOutlet var passwordTextField: NSTextField?
}


enum PlayerId: Int {
    case none = -1
    case audio = 0
    case video = 1
}

struct PlayerItemTime {
    var hours: Int = 0
    var minutes: Int = 0
    var seconds: Int = 0
    
    init(hours: Int, minutes: Int, seconds: Int) {
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
    }
}

enum RequestId: Int {
    case playerPropertyPercentageSpeed = 1
    case applicationVolume = 2
    case playlistGetItems = 3
    case playerGetItem = 4
    case playerGetActivePlayers = 5
    case playerGetPropertyPlaylistPosition = 6
}

enum NotificationId: String {
    case applicationOnVolumeChanged = "Application.OnVolumeChanged"
    case playerOnPlay = "Player.OnPlay"
    case playerOnPause = "Player.OnPause"
    case playerOnStop = "Player.OnStop"
    case playlistOnAdd = "Playlist.OnAdd"
    case inputOnInputRequested = "Input.OnInputRequested"
    case inputOnInputFinished = "Input.OnInputFinished"
}

enum KeyboardBehavior {
    case command
    case textInput
}

enum KeyboardKey: UInt16 {
    case s = 1
    case f = 3
    case h = 4
    case x = 7
    case c = 8
    case v = 9
    case b = 11
    case r = 15
    case u = 32
    case i = 34
    case p = 35
    case ret = 36
    case n = 45
    case m = 46
    case tab = 48
    case space = 49
    case back = 51
    case escape = 53
    case left = 123
    case right = 124
    case down = 125
    case up = 126
}
