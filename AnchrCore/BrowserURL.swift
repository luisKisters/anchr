import ApplicationServices
import Foundation

/// Reads the address of the page in the front window, without knowing which browser it is.
///
/// Deliberately not AppleScript. Scripting each browser means a separate dialect for
/// Safari, Chrome, Arc and Edge, an Automation permission prompt per app, and nothing at
/// all for a browser nobody wrote a case for. Accessibility gives one path: WebKit and
/// Chromium both expose an `AXWebArea` element carrying `AXURL`, so every browser built
/// on either engine answers the same question the same way.
public enum BrowserURL {
    /// Bounded on purpose. A browser window is a deep tree and this runs on every focus
    /// change, so the search gives up rather than walking a whole page.
    static let maximumDepth = 12
    static let maximumNodes = 600

    private static let webAreaRole = "AXWebArea"
    private static let urlAttribute = "AXURL"

    public static func read(processIdentifier: Int32) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let application = AXUIElementCreateApplication(processIdentifier)
        guard let window = attribute(application, kAXFocusedWindowAttribute as String)
            as! AXUIElement?
        else { return nil }
        var budget = maximumNodes
        return findURL(in: window, depth: 0, budget: &budget)
    }

    private static func findURL(in element: AXUIElement, depth: Int, budget: inout Int) -> String? {
        guard depth <= maximumDepth, budget > 0 else { return nil }
        budget -= 1

        if role(of: element) == webAreaRole, let url = url(of: element) {
            return url
        }
        // Some browsers hang the URL on an element that is not the web area itself, so a
        // direct hit is checked before descending, but a miss is not fatal.
        if let url = url(of: element) {
            return url
        }

        guard let children = attribute(element, kAXChildrenAttribute as String) as? [AXUIElement]
        else { return nil }
        for child in children {
            if let found = findURL(in: child, depth: depth + 1, budget: &budget) {
                return found
            }
        }
        return nil
    }

    private static func url(of element: AXUIElement) -> String? {
        guard let value = attribute(element, urlAttribute) else { return nil }
        if let url = value as! URL? {
            return normalize(url.absoluteString)
        }
        if let string = value as? String {
            return normalize(string)
        }
        return nil
    }

    /// A URL can carry a session token or a search query, and it goes straight into a
    /// prompt sent to a third party. Host plus path is enough to tell YouTube from a code
    /// review; the query string is not worth the leak.
    private static func normalize(_ raw: String) -> String? {
        guard let components = URLComponents(string: raw),
              let host = components.host,
              components.scheme == "http" || components.scheme == "https"
        else { return nil }
        let path = components.path == "/" ? "" : components.path
        return host + path
    }

    private static func role(of element: AXUIElement) -> String? {
        attribute(element, kAXRoleAttribute as String) as? String
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> Any? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }
}
