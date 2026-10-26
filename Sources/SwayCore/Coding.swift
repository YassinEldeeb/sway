import Foundation

extension KeyedDecodingContainer {
    /// Decodes a value if present and readable, else nil. Saved files from
    /// an older version (missing keys) or with one damaged field keep the
    /// rest of their data.
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}

/// Short local times for user-facing explanations ("next possible at 10:25").
public enum Clock {
    public static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: d)
    }
}
