import Foundation

/// `open Myna.app --args -demo`: made-up texts and no phone connection, for screenshots.
/// Real screenshots would publish someone's texts, contacts and pairing key.
enum Demo {
    static let on = CommandLine.arguments.contains("-demo")

    /// What to show for the screenshot: `-demo messages|loading|ads|blocked|settings|about|pair`.
    static var scene: String {
        let a = CommandLine.arguments
        return a.firstIndex(of: "-demo").flatMap { a.indices.contains($0 + 1) ? a[$0 + 1] : nil } ?? "messages"
    }

    /// Separate from the real settings, so demo blocks and reads never touch them.
    static let store: UserDefaults = {
        let d = UserDefaults(suiteName: "com.truthofmatthew.Myna.demo")!
        d.removePersistentDomain(forName: "com.truthofmatthew.Myna.demo")
        d.set(["+15550188", "PromoClub", "WinBig"], forKey: "blocked")
        return d
    }()

    /// A pairing code that pairs with nothing.
    static let pairingKey = Data(repeating: 0x5A, count: 32)

    static func texts() -> [[String: Any]] {
        let now = Date().timeIntervalSince1970 * 1000
        var id: Int64 = 1000
        func m(_ thread: Int64, _ address: String, _ name: String?, _ minutesAgo: Double, _ body: String, mine: Bool = false, read: Bool = true) -> [String: Any] {
            id += 1
            var d: [String: Any] = ["id": id, "thread": thread, "address": address, "body": body,
                                    "date": now - minutesAgo * 60_000, "type": mine ? 2 : 1, "read": read]
            if let name { d["name"] = name }
            return d
        }
        let sara = "+15550142", nima = "+15550199", mom = "+15550111", bank = "BlueBank", shop = "MegaMart", deli = "+15550177"
        return [
            m(1, sara, "Sara Karimi", 182, "Are we still on for lunch tomorrow?"),
            m(1, sara, "Sara Karimi", 180, "Yes! 12:30 at the usual place?", mine: true),
            m(1, sara, "Sara Karimi", 178, "Perfect. I'll book a table."),
            m(1, sara, "Sara Karimi", 6, "Running 10 minutes late, order me the soup 🙏", read: false),
            m(2, nima, "Nima", 300, "سلام! فایل‌ها رو فرستادی؟"),
            m(2, nima, "Nima", 296, "آره، الان چک کن. اگه چیزی کم بود بگو.", mine: true),
            m(2, nima, "Nima", 41, "رسید، مرسی. فردا صبح جلسه داریم یادت نره", read: false),
            m(3, mom, "Mom", 1440, "Did you eat?"),
            m(3, mom, "Mom", 1435, "Yes mom 😄", mine: true),
            m(4, bank, nil, 95, "BlueBank: $42.80 card payment at Corner Café. Balance $1,204.17."),
            m(5, shop, nil, 120, "MegaMart: 50% OFF everything this weekend only! Shop now: megamart.example/sale"),
            m(6, deli, nil, 240, "🍕 تخفیف ۳۰٪ پیتزا فقط امشب! کد: PIZZA30"),
            m(7, "+15550123", nil, 2000, "Your parcel is out for delivery and will arrive today between 2 and 5 pm."),
        ]
    }

    static func adVerdicts() -> [AdVerdict] {
        [AdVerdict(address: "MegaMart", title: "MegaMart", sample: "MegaMart: 50% OFF everything this weekend only! Shop now: megamart.example/sale",
                   isAd: true, confidence: 0.97, reason: "Store discount campaign"),
         AdVerdict(address: "+15550177", title: "+15550177", sample: "🍕 تخفیف ۳۰٪ پیتزا فقط امشب! کد: PIZZA30",
                   isAd: true, confidence: 0.93, reason: "Restaurant promo code"),
         AdVerdict(address: "+15550123", title: "+15550123", sample: "Your parcel is out for delivery and will arrive today between 2 and 5 pm.",
                   isAd: false, confidence: 0.08, reason: "Delivery notice"),
         AdVerdict(address: "BlueBank", title: "BlueBank", sample: "BlueBank: $42.80 card payment at Corner Café. Balance $1,204.17.",
                   isAd: false, confidence: 0.04, reason: "Bank payment alert")]
    }
}
