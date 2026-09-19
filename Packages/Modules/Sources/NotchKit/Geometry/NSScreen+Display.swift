import AppKit

public extension NSScreen {
    /// A stable identifier for the physical display, surviving reboots and cable/port changes —
    /// unlike `CGDirectDisplayID`, which can be reassigned across a display reconfiguration — so
    /// a saved edge/screen preference keeps pointing at the same monitor.
    var displayIdentifier: String? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screenNumber = deviceDescription[key] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(screenNumber.uint32Value)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
