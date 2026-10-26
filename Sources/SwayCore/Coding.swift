import Foundation

extension KeyedDecodingContainer {
    /// Decodes a value if present and readable, else nil. Saved files from
    /// an older version (missing keys) or with one damaged field keep the
    /// rest of their data.
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }

    /// A list that keeps every element it can read: one entry written by a
    /// newer version (an unknown kind) doesn't cost the others.
    func lenientList<T: Decodable>(_ type: T.Type, _ key: Key) -> [T]? {
        lenient([Lossy<T>].self, key).map { $0.compactMap(\.value) }
    }

    /// A map keyed by an enum that keeps every entry it can read: an
    /// unknown key or an unreadable value drops only that entry.
    func lenientMap<K: RawRepresentable & Hashable, V: Decodable>(_ keys: K.Type, _ values: V.Type, _ key: Key) -> [K: V]? where K.RawValue == String {
        guard let raw = lenient([String: Lossy<V>].self, key) else { return nil }
        var out: [K: V] = [:]
        for (k, v) in raw {
            if let k = K(rawValue: k), let v = v.value { out[k] = v }
        }
        return out
    }
}

/// Decodes to nil instead of failing.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    // Through the container, so the decoder's date format applies.
    init(from decoder: Decoder) throws { value = try? decoder.singleValueContainer().decode(T.self) }
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
