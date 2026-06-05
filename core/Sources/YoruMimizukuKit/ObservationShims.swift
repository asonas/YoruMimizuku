#if !canImport(Combine)
/// Minimal stand-ins for Combine's `ObservableObject` / `@Published` so the pure
/// view models compile on platforms without Combine (e.g. Windows). On Apple,
/// Combine supplies the real types and this file is excluded.
///
/// These are deliberately no-op: the Windows front end drives its UI through the
/// C ABI bridge with its own (C#) view models, not these SwiftUI-oriented ones.
/// They exist only so the shared view-model layer keeps type-checking everywhere.
/// (The view models use neither `$`-projected publishers nor `objectWillChange`,
/// so no-op wrappers are sufficient.)
public protocol ObservableObject: AnyObject {}

@propertyWrapper
public struct Published<Value> {
    public var wrappedValue: Value

    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
}
#endif
