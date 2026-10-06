#!/usr/bin/swift
import CoreGraphics
import Foundation

let betterDisplay = "/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"
let virtualName = ProcessInfo.processInfo.environment["REMOTE_DISPLAY_NAME"] ?? "Virtual Remote"

struct Identity {
    let vendor: UInt32
    let model: UInt32
    let serial: UInt32
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

@discardableResult
func runBetterDisplay(_ args: [String]) -> Data {
    let p = Process()
    let out = Pipe()
    p.executableURL = URL(fileURLWithPath: betterDisplay)
    p.arguments = args
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { fail("BetterDisplay not found at \(betterDisplay)") }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return data
}

// BetterDisplay reports displayID 0 for its virtual screens even while they are
// online, so the CoreGraphics display is matched by EDID-style identity instead.
func virtualIdentity() -> Identity {
    let data = runBetterDisplay(["get", "-name=\(virtualName)", "-identifiers"])
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          json["deviceType"] as? String == "VirtualScreen",
          let vendor = UInt32(json["vendor"] as? String ?? ""),
          let model = UInt32(json["model"] as? String ?? ""),
          let serial = UInt32(json["serial"] as? String ?? "")
    else { fail("no BetterDisplay virtual screen named \"\(virtualName)\"") }
    return Identity(vendor: vendor, model: model, serial: serial)
}

func onlineDisplays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetOnlineDisplayList(count, &ids, &count)
    return Array(ids.prefix(Int(count)))
}

func matches(_ id: CGDirectDisplayID, _ identity: Identity) -> Bool {
    CGDisplayVendorNumber(id) == identity.vendor
        && CGDisplayModelNumber(id) == identity.model
        && CGDisplaySerialNumber(id) == identity.serial
}

func virtualDisplay(_ identity: Identity, waitSeconds: Int) -> CGDirectDisplayID? {
    for attempt in 0...(waitSeconds * 2) {
        if let id = onlineDisplays().first(where: { matches($0, identity) }) { return id }
        if attempt < waitSeconds * 2 { usleep(500_000) }
    }
    return nil
}

func screenLocked() -> Bool {
    let session = CGSessionCopyCurrentDictionary() as? [String: Any]
    return session?["CGSSessionScreenIsLocked"] as? Bool ?? false
}

func configure(_ body: (CGDisplayConfigRef?) -> Void) {
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success else { fail("CGBeginDisplayConfiguration failed") }
    body(config)
    let result = CGCompleteDisplayConfiguration(config, .forSession)
    guard result == .success else { fail("display configuration rejected (CGError \(result.rawValue))") }
}

func turnOn(width: Int, height: Int) {
    if screenLocked() { fail("screen is locked: WindowServer rejects mode changes until the session is unlocked") }
    let identity = virtualIdentity()
    runBetterDisplay(["set", "-name=\(virtualName)", "-connected=on"])
    guard let virtual = virtualDisplay(identity, waitSeconds: 10) else { fail("\(virtualName) did not come online") }

    let modes = CGDisplayCopyAllDisplayModes(virtual, nil) as? [CGDisplayMode] ?? []
    guard let mode = modes.first(where: { $0.pixelWidth == width && $0.pixelHeight == height && $0.width == width })
    else { fail("\(virtualName) has no \(width)x\(height) mode") }

    configure { config in
        CGConfigureDisplayWithDisplayMode(config, virtual, mode, nil)
        CGConfigureDisplayOrigin(config, virtual, 0, 0)
        for id in onlineDisplays() where id != virtual {
            CGConfigureDisplayMirrorOfDisplay(config, id, virtual)
        }
    }
}

func turnOff() {
    let identity = virtualIdentity()
    configure { config in
        for id in onlineDisplays() {
            CGConfigureDisplayMirrorOfDisplay(config, id, kCGNullDirectDisplay)
        }
    }
    if let virtual = virtualDisplay(identity, waitSeconds: 0), CGDisplayIsMain(virtual) != 0,
       let physical = onlineDisplays().first(where: { CGDisplayIsBuiltin($0) != 0 }) ?? onlineDisplays().first(where: { $0 != virtual }) {
        configure { CGConfigureDisplayOrigin($0, physical, 0, 0) }
    }
    runBetterDisplay(["set", "-name=\(virtualName)", "-connected=off"])
}

func printStatus() {
    let identity = virtualIdentity()
    if screenLocked() { print("screen locked") }
    for id in onlineDisplays() {
        let mode = CGDisplayCopyDisplayMode(id)
        let mirror = CGDisplayMirrorsDisplay(id)
        var line = "\(id) \(matches(id, identity) ? "virtual" : "physical") \(mode?.pixelWidth ?? 0)x\(mode?.pixelHeight ?? 0)"
        if CGDisplayIsMain(id) != 0 { line += " main" }
        if mirror != kCGNullDirectDisplay { line += " mirrors \(mirror)" }
        print(line)
    }
}

let usage = "usage: remote-display on [WIDTHxHEIGHT] | off | status"
let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "on":
    let size = (args.count > 1 ? args[1] : "1920x1080").split(separator: "x").compactMap { Int($0) }
    guard size.count == 2 else { fail(usage) }
    turnOn(width: size[0], height: size[1])
case "off":
    turnOff()
case "status", nil:
    break
default:
    fail(usage)
}
printStatus()
