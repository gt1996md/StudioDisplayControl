#!/usr/bin/env swift
// StudioDisplayControl.swift
// A macOS menu bar utility to simultaneously control volume and brightness
// across all connected Apple Studio Displays.
//
// Features:
//   - Intercepts keyboard volume keys (F10/F11/F12) to sync volume across all Studio Displays
//   - Intercepts keyboard brightness keys (F1/F2) to sync brightness across all Studio Displays
//   - Menu bar sliders for manual adjustment
//   - Hot-plug support with automatic device detection
//
// Build: swiftc -O -framework CoreAudio -framework AppKit -framework Carbon -framework IOKit StudioDisplayControl.swift -o StudioDisplayControl
// Note: Requires Accessibility permission in System Settings > Privacy & Security > Accessibility

import Cocoa
import CoreAudio
import Carbon
import IOKit
import IOKit.graphics

// ============================================================================
// MARK: - Brightness Control (DisplayServices private framework)
// ============================================================================

@_silgen_name("DisplayServicesGetBrightness")
func DisplayServicesGetBrightness(_ display: CGDirectDisplayID, _ brightness: UnsafeMutablePointer<Float>) -> Int32

@_silgen_name("DisplayServicesSetBrightness")
func DisplayServicesSetBrightness(_ display: CGDirectDisplayID, _ brightness: Float) -> Int32

func findAppleExternalDisplays() -> [CGDirectDisplayID] {
    var onlineDisplays = [CGDirectDisplayID](repeating: 0, count: 16)
    var displayCount: UInt32 = 0
    guard CGGetOnlineDisplayList(16, &onlineDisplays, &displayCount) == .success else { return [] }

    return Array(onlineDisplays.prefix(Int(displayCount))).filter { displayID in
        let isApple = CGDisplayVendorNumber(displayID) == 0x610
        let isExternal = CGDisplayIsBuiltin(displayID) == 0
        return isApple && isExternal
    }
}

func getBrightness(_ displayID: CGDirectDisplayID) -> Float? {
    var brightness: Float = 0
    let result = DisplayServicesGetBrightness(displayID, &brightness)
    return result == 0 ? brightness : nil
}

func setBrightness(_ displayID: CGDirectDisplayID, _ value: Float) {
    let clamped = max(0, min(1, value))
    _ = DisplayServicesSetBrightness(displayID, clamped)
}

// ============================================================================
// MARK: - Audio Control (CoreAudio)
// ============================================================================

func getAllAudioDevices() -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
    ) == noErr else { return [] }

    let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
    var devices = [AudioDeviceID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &devices
    ) == noErr else { return [] }
    return devices
}

func getDeviceName(_ id: AudioDeviceID) -> String {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = UInt32(MemoryLayout<CFString>.size)
    var name: CFString = "" as CFString
    AudioObjectGetPropertyData(id, &address, 0, nil, &dataSize, &name)
    return name as String
}

func hasOutputChannels(_ id: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &dataSize) == noErr else { return false }

    let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(dataSize))
    defer { bufferListPointer.deallocate() }
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &dataSize, bufferListPointer) == noErr else { return false }

    let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
    return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
}

func findStudioDisplayAudioDevices() -> [AudioDeviceID] {
    return getAllAudioDevices().filter { id in
        let name = getDeviceName(id)
        return name.contains("Studio Display") && hasOutputChannels(id)
    }
}

func getVolume(_ id: AudioDeviceID) -> Float? {
    var volume: Float32 = 0
    var size = UInt32(MemoryLayout<Float32>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    if AudioObjectGetPropertyData(id, &address, 0, nil, &size, &volume) == noErr {
        return volume
    }
    address.mElement = 1
    if AudioObjectGetPropertyData(id, &address, 0, nil, &size, &volume) == noErr {
        return volume
    }
    return nil
}

func setVolume(_ id: AudioDeviceID, _ volume: Float32) {
    var vol = max(0, min(1, volume))
    let size = UInt32(MemoryLayout<Float32>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    var settable: DarwinBoolean = false
    if AudioObjectIsPropertySettable(id, &address, &settable) == noErr, settable.boolValue {
        AudioObjectSetPropertyData(id, &address, 0, nil, size, &vol)
        return
    }
    for ch: UInt32 in 1...2 {
        address.mElement = ch
        if AudioObjectIsPropertySettable(id, &address, &settable) == noErr, settable.boolValue {
            AudioObjectSetPropertyData(id, &address, 0, nil, size, &vol)
        }
    }
}

func setMute(_ id: AudioDeviceID, _ mute: Bool) {
    var val: UInt32 = mute ? 1 : 0
    let size = UInt32(MemoryLayout<UInt32>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    AudioObjectSetPropertyData(id, &address, 0, nil, size, &val)
}

// ============================================================================
// MARK: - Media Key Constants
// ============================================================================

let NX_KEYTYPE_SOUND_UP: Int32        = 0
let NX_KEYTYPE_SOUND_DOWN: Int32      = 1
let NX_KEYTYPE_BRIGHTNESS_UP: Int32   = 2
let NX_KEYTYPE_BRIGHTNESS_DOWN: Int32 = 3
let NX_KEYTYPE_MUTE: Int32           = 7
let NX_SYSDEFINED_RAW: UInt32        = 14

// ============================================================================
// MARK: - AppDelegate
// ============================================================================

class AppDelegate: NSObject, NSApplicationDelegate {

    // --- UI ---
    var statusItem: NSStatusItem!
    var volumeSlider: NSSlider!
    var brightnessSlider: NSSlider!
    var volumeLabel: NSMenuItem!
    var brightnessLabel: NSMenuItem!
    var deviceCountItem: NSMenuItem!

    // --- State ---
    var currentVolume: Float = 0.5
    var currentBrightness: Float = 0.5
    var isMuted: Bool = false

    // --- Devices ---
    var audioDevices: [AudioDeviceID] = []
    var displayIDs: [CGDirectDisplayID] = []
    var eventTap: CFMachPort?

    let step: Float = 1.0 / 16.0

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        refreshDevices()
        readCurrentState()
        setupMenuBar()
        setupEventTap()

        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.refreshDevices()
            self?.updateDeviceCount()
        }
    }

    func refreshDevices() {
        audioDevices = findStudioDisplayAudioDevices()
        displayIDs = findAppleExternalDisplays()
    }

    func readCurrentState() {
        if let first = audioDevices.first, let vol = getVolume(first) {
            currentVolume = vol
        }
        if let first = displayIDs.first, let br = getBrightness(first) {
            currentBrightness = br
        }
    }

    // MARK: Menu Bar UI

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()

        let menu = NSMenu()

        // ── Device Info ──
        deviceCountItem = NSMenuItem(title: deviceCountText(), action: nil, keyEquivalent: "")
        deviceCountItem.isEnabled = false
        menu.addItem(deviceCountItem)
        menu.addItem(NSMenuItem.separator())

        // ── Volume Section ──
        let volHeader = NSMenuItem(title: "🔊 Volume", action: nil, keyEquivalent: "")
        volHeader.isEnabled = false
        menu.addItem(volHeader)

        volumeLabel = NSMenuItem(title: volumeText(), action: nil, keyEquivalent: "")
        volumeLabel.isEnabled = false
        menu.addItem(volumeLabel)

        let volSliderItem = NSMenuItem()
        volumeSlider = NSSlider(value: Double(currentVolume), minValue: 0, maxValue: 1,
                                target: self, action: #selector(volumeSliderChanged(_:)))
        volumeSlider.frame = NSRect(x: 20, y: 4, width: 200, height: 24)
        volumeSlider.isContinuous = true
        let volView = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 32))
        volView.addSubview(volumeSlider)
        volSliderItem.view = volView
        menu.addItem(volSliderItem)

        let muteItem = NSMenuItem(title: "Mute", action: #selector(toggleMute), keyEquivalent: "m")
        muteItem.target = self
        menu.addItem(muteItem)
        menu.addItem(NSMenuItem.separator())

        // ── Brightness Section ──
        let brHeader = NSMenuItem(title: "☀️ Brightness", action: nil, keyEquivalent: "")
        brHeader.isEnabled = false
        menu.addItem(brHeader)

        brightnessLabel = NSMenuItem(title: brightnessText(), action: nil, keyEquivalent: "")
        brightnessLabel.isEnabled = false
        menu.addItem(brightnessLabel)

        let brSliderItem = NSMenuItem()
        brightnessSlider = NSSlider(value: Double(currentBrightness), minValue: 0, maxValue: 1,
                                    target: self, action: #selector(brightnessSliderChanged(_:)))
        brightnessSlider.frame = NSRect(x: 20, y: 4, width: 200, height: 24)
        brightnessSlider.isContinuous = true
        let brView = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 32))
        brView.addSubview(brightnessSlider)
        brSliderItem.view = brView
        menu.addItem(brSliderItem)
        menu.addItem(NSMenuItem.separator())

        // ── Actions ──
        let refreshItem = NSMenuItem(title: "Refresh Devices", action: #selector(refreshAndUpdate), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: Labels & Icon

    func deviceCountText() -> String {
        return "Studio Display: Audio ×\(audioDevices.count)  Display ×\(displayIDs.count)"
    }

    func volumeText() -> String {
        if isMuted { return "  Volume: Muted" }
        return "  Volume: \(Int(currentVolume * 100))%"
    }

    func brightnessText() -> String {
        return "  Brightness: \(Int(currentBrightness * 100))%"
    }

    func updateIcon() {
        if isMuted || currentVolume == 0 {
            statusItem?.button?.title = "🖥️🔇"
        } else {
            statusItem?.button?.title = "🖥️"
        }
    }

    func updateDeviceCount() {
        deviceCountItem?.title = deviceCountText()
    }

    func updateVolumeUI() {
        volumeSlider?.doubleValue = Double(currentVolume)
        volumeLabel?.title = volumeText()
        updateIcon()
    }

    func updateBrightnessUI() {
        brightnessSlider?.doubleValue = Double(currentBrightness)
        brightnessLabel?.title = brightnessText()
    }

    // MARK: Slider Callbacks

    @objc func volumeSliderChanged(_ sender: NSSlider) {
        currentVolume = Float(sender.doubleValue)
        isMuted = false
        applyVolumeToAll()
        volumeLabel?.title = volumeText()
        updateIcon()
    }

    @objc func brightnessSliderChanged(_ sender: NSSlider) {
        currentBrightness = Float(sender.doubleValue)
        applyBrightnessToAll()
        brightnessLabel?.title = brightnessText()
    }

    @objc func toggleMute() {
        isMuted.toggle()
        for id in audioDevices { setMute(id, isMuted) }
        updateVolumeUI()
    }

    @objc func refreshAndUpdate() {
        refreshDevices()
        readCurrentState()
        updateDeviceCount()
        updateVolumeUI()
        updateBrightnessUI()
    }

    // MARK: Apply to All Devices

    func applyVolumeToAll() {
        for id in audioDevices {
            setVolume(id, currentVolume)
            if !isMuted { setMute(id, false) }
        }
    }

    func applyBrightnessToAll() {
        for id in displayIDs {
            setBrightness(id, currentBrightness)
        }
    }

    // MARK: Media Key Interception

    func setupEventTap() {
        let mask = CGEventMask(1 << NX_SYSDEFINED_RAW)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = delegate.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            guard type.rawValue == 14,
                  let nsEvent = NSEvent(cgEvent: event),
                  nsEvent.subtype.rawValue == 8 else {
                return Unmanaged.passUnretained(event)
            }

            let data = nsEvent.data1
            let keyCode = Int32((data & 0xFFFF0000) >> 16)
            let keyFlags = (data & 0x0000FF00) >> 8
            let isDown = (keyFlags & 0x0A) != 0

            guard isDown else { return Unmanaged.passUnretained(event) }

            switch keyCode {

            // ── Volume ──
            case NX_KEYTYPE_SOUND_UP:
                delegate.currentVolume = min(1.0, delegate.currentVolume + delegate.step)
                delegate.isMuted = false
                delegate.applyVolumeToAll()
                DispatchQueue.main.async { delegate.updateVolumeUI() }
                return nil

            case NX_KEYTYPE_SOUND_DOWN:
                delegate.currentVolume = max(0.0, delegate.currentVolume - delegate.step)
                delegate.isMuted = false
                delegate.applyVolumeToAll()
                DispatchQueue.main.async { delegate.updateVolumeUI() }
                return nil

            case NX_KEYTYPE_MUTE:
                delegate.isMuted.toggle()
                for id in delegate.audioDevices { setMute(id, delegate.isMuted) }
                DispatchQueue.main.async { delegate.updateVolumeUI() }
                return nil

            // ── Brightness ──
            case NX_KEYTYPE_BRIGHTNESS_UP:
                delegate.currentBrightness = min(1.0, delegate.currentBrightness + delegate.step)
                delegate.applyBrightnessToAll()
                DispatchQueue.main.async { delegate.updateBrightnessUI() }
                return nil

            case NX_KEYTYPE_BRIGHTNESS_DOWN:
                delegate.currentBrightness = max(0.0, delegate.currentBrightness - delegate.step)
                delegate.applyBrightnessToAll()
                DispatchQueue.main.async { delegate.updateBrightnessUI() }
                return nil

            default:
                return Unmanaged.passUnretained(event)
            }
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap = eventTap else {
            let alert = NSAlert()
            alert.messageText = "Unable to Create Event Tap"
            alert.informativeText = "Please grant Accessibility permission in System Settings > Privacy & Security > Accessibility, then relaunch the app."
            alert.alertStyle = .critical
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

// ============================================================================
// MARK: - Entry Point
// ============================================================================

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.run()
