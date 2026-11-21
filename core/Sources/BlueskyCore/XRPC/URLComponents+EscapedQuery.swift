import Foundation

extension URLComponents {
    /// Query items with `+` percent-encoded. `queryItems` leaves `+` as is, and
    /// servers decode it as a space, so a cursor or search term containing `+`
    /// would arrive changed.
    var escapedQueryItems: [URLQueryItem]? {
        get { queryItems }
        set {
            queryItems = newValue
            percentEncodedQuery = percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
    }
}
