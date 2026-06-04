import Foundation

/// Encodes key/value pairs into an `application/x-www-form-urlencoded` body.
/// Spaces and all reserved characters are percent-encoded (space → `%20`),
/// which atproto authorization servers accept for PAR and token requests.
public enum FormURLEncoder {
    /// RFC 3986 unreserved characters: ALPHA / DIGIT / "-" / "." / "_" / "~".
    private static let unreserved: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return set
    }()

    public static func encode(_ pairs: [(String, String)]) -> Data {
        let joined = pairs
            .map { "\(escape($0.0))=\(escape($0.1))" }
            .joined(separator: "&")
        return Data(joined.utf8)
    }

    private static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
}
