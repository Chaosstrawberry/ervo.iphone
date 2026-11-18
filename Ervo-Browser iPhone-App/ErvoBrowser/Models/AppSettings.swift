import SwiftUI

enum ThemeMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String { L.t("mode_\(rawValue)") }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum Accent: String, Codable, CaseIterable, Identifiable {
    case erde, ozean, wald, sonne, lavendel, kirsche, sand, graphit

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .erde: return Color(hex: 0x2F855A)
        case .ozean: return Color(hex: 0x1A73E8)
        case .wald: return Color(hex: 0x2E7D32)
        case .sonne: return Color(hex: 0xE8710A)
        case .lavendel: return Color(hex: 0x7C4DFF)
        case .kirsche: return Color(hex: 0xD81B60)
        case .sand: return Color(hex: 0xA0784F)
        case .graphit: return Color(hex: 0x5F6368)
        }
    }

    var title: String {
        switch self {
        case .erde: return L.isGerman ? "Erde" : "Earth"
        case .ozean: return L.isGerman ? "Ozean" : "Ocean"
        case .wald: return L.isGerman ? "Wald" : "Forest"
        case .sonne: return L.isGerman ? "Sonnenuntergang" : "Sunset"
        case .lavendel: return L.isGerman ? "Lavendel" : "Lavender"
        case .kirsche: return L.isGerman ? "Kirsche" : "Cherry"
        case .sand: return "Sand"
        case .graphit: return L.isGerman ? "Graphit" : "Graphite"
        }
    }
}

enum SearchEngine: String, Codable, CaseIterable, Identifiable {
    case google, duckduckgo, bing, brave, ecosia, startpage, custom

    var id: String { rawValue }

    var name: String {
        switch self {
        case .google: return "Google"
        case .duckduckgo: return "DuckDuckGo"
        case .bing: return "Bing"
        case .brave: return "Brave Search"
        case .ecosia: return "Ecosia"
        case .startpage: return "Startpage"
        case .custom: return L.t("customEngine")
        }
    }

    fileprivate var template: String {
        switch self {
        case .google, .custom: return "https://www.google.com/search?q=%s"
        case .duckduckgo: return "https://duckduckgo.com/?q=%s"
        case .bing: return "https://www.bing.com/search?q=%s"
        case .brave: return "https://search.brave.com/search?q=%s"
        case .ecosia: return "https://www.ecosia.org/search?q=%s"
        case .startpage: return "https://www.startpage.com/do/search?query=%s"
        }
    }

    /// Inserts the percent-encoded query into a template containing "%s".
    static func fill(_ template: String, query: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#/")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return URL(string: template.replacingOccurrences(of: "%s", with: encoded))
    }
}

enum AddressBarPosition: String, Codable, CaseIterable, Identifiable {
    case top, bottom

    var id: String { rawValue }
    var title: String { L.t("addressBar_\(rawValue)") }
}

struct AppSettings: Codable, Equatable {
    var themeMode: ThemeMode = .system
    var accent: Accent = .erde
    var searchEngine: SearchEngine = .google
    var customSearchURL: String = ""
    var adblock: Bool = true
    var adblockWhitelist: [String] = []
    var addressBarPosition: AddressBarPosition = .bottom
    var restoreTabs: Bool = true
    var textZoom: Int = 100
    var hiddenSites: [String] = []
    var onboarded: Bool = false

    init() {}

    // Tolerant decoding: unknown or missing values fall back to defaults (safe across app updates).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        themeMode = (try? c.decode(ThemeMode.self, forKey: .themeMode)) ?? d.themeMode
        accent = (try? c.decode(Accent.self, forKey: .accent)) ?? d.accent
        searchEngine = (try? c.decode(SearchEngine.self, forKey: .searchEngine)) ?? d.searchEngine
        customSearchURL = (try? c.decode(String.self, forKey: .customSearchURL)) ?? d.customSearchURL
        adblock = (try? c.decode(Bool.self, forKey: .adblock)) ?? d.adblock
        adblockWhitelist = (try? c.decode([String].self, forKey: .adblockWhitelist)) ?? d.adblockWhitelist
        addressBarPosition = (try? c.decode(AddressBarPosition.self, forKey: .addressBarPosition)) ?? d.addressBarPosition
        restoreTabs = (try? c.decode(Bool.self, forKey: .restoreTabs)) ?? d.restoreTabs
        textZoom = (try? c.decode(Int.self, forKey: .textZoom)) ?? d.textZoom
        hiddenSites = (try? c.decode([String].self, forKey: .hiddenSites)) ?? d.hiddenSites
        onboarded = (try? c.decode(Bool.self, forKey: .onboarded)) ?? d.onboarded
    }

    func isWhitelisted(_ url: URL?) -> Bool {
        guard let host = url?.host()?.lowercased() else { return false }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return adblockWhitelist.contains { bare == $0 || bare.hasSuffix("." + $0) }
    }

    static func isValidCustomSearch(_ template: String) -> Bool {
        let lower = template.lowercased()
        guard lower.hasPrefix("https://") || lower.hasPrefix("http://"), template.contains("%s") else { return false }
        return URL(string: template.replacingOccurrences(of: "%s", with: "x")) != nil
    }

    /// Search URL for the selected engine (a broken custom engine falls back to Google).
    func searchURL(for query: String) -> URL? {
        if searchEngine == .custom, Self.isValidCustomSearch(customSearchURL) {
            return SearchEngine.fill(customSearchURL, query: query)
        }
        return SearchEngine.fill(searchEngine.template, query: query)
    }

    var searchEngineName: String {
        if searchEngine == .custom, Self.isValidCustomSearch(customSearchURL),
           let host = URL(string: customSearchURL.replacingOccurrences(of: "%s", with: "x"))?.host() {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        return searchEngine == .custom ? SearchEngine.google.name : searchEngine.name
    }

    /// Text zoom limited to sensible values (50–300 %).
    var clampedTextZoom: Int { min(300, max(50, textZoom)) }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
