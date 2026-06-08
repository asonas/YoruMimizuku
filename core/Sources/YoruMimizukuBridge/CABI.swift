#if canImport(WinSDK)
import Foundation
import BlueskyCore
import YoruMimizukuKit

// MARK: - C ABI conventions
//
// Every entry point takes a single UTF-8 JSON request string and returns a
// newly-allocated UTF-8 JSON response string the caller MUST release with
// `yoru_free`. Responses are always one of:
//   { "ok": true,  "data": <payload> }
//   { "ok": false, "error": "<message>" }

// MARK: Request payloads

private struct InitReq: Decodable, Sendable {
    let service: String
    let clientID: String
    let redirectURI: String
    let scope: String
}
private struct EmptyReq: Decodable, Sendable {}
private struct HandleReq: Decodable, Sendable { let handle: String }
private struct LoginCompleteReq: Decodable, Sendable { let pendingId: String; let callbackUrl: String }
private struct DidReq: Decodable, Sendable { let did: String }
private struct CursorReq: Decodable, Sendable { let cursor: String? }
private struct ActorFeedReq: Decodable, Sendable { let actor: String; let cursor: String? }
private struct ActorReq: Decodable, Sendable { let actor: String }
private struct UriReq: Decodable, Sendable { let uri: String }
private struct SearchReq: Decodable, Sendable { let filter: SavedFilter; let cursor: String? }
private struct LikeReq: Decodable, Sendable { let uri: String; let cid: String }
private struct RecordReq: Decodable, Sendable { let recordUri: String }
private struct PermalinkReq: Decodable, Sendable { let id: String; let authorHandle: String }
private struct ImageReq: Decodable, Sendable { let dataBase64: String; let mimeType: String; let alt: String }
private struct QuoteReq: Decodable, Sendable { let uri: String; let cid: String }
private struct DraftReq: Decodable, Sendable {
    let text: String
    let images: [ImageReq]?
    let replyParentURI: String?
    let quote: QuoteReq?

    func toDraft() -> PostDraft {
        let composeImages: [ComposeImage] = (images ?? []).compactMap { image in
            guard let data = Data(base64Encoded: image.dataBase64) else { return nil }
            return ComposeImage(data: data, mimeType: image.mimeType, alt: image.alt)
        }
        let quoteRef = quote.map { StrongRef(uri: $0.uri, cid: $0.cid) }
        return PostDraft(text: text, images: composeImages, replyParentURI: replyParentURI, quote: quoteRef)
    }
}

// MARK: Envelope helpers

private struct SuccessEnvelope<T: Encodable>: Encodable {
    let ok = true
    let data: T
}
private struct ErrorEnvelope: Encodable {
    let ok = false
    let error: String
}

private func makeResponse<T: Encodable>(_ value: T) -> UnsafeMutablePointer<CChar>? {
    let encoder = JSONEncoder()
    if let data = try? encoder.encode(SuccessEnvelope(data: value)),
       let string = String(data: data, encoding: .utf8) {
        return strdup(string)
    }
    return makeError("failed to encode response")
}

private func makeError(_ message: String) -> UnsafeMutablePointer<CChar>? {
    if let data = try? JSONEncoder().encode(ErrorEnvelope(error: message)),
       let string = String(data: data, encoding: .utf8) {
        return strdup(string)
    }
    return strdup(#"{"ok":false,"error":"unknown"}"#)
}

private func decodeRequest<Req: Decodable>(_ input: UnsafePointer<CChar>?, as type: Req.Type) throws -> Req {
    let json = input.map { String(cString: $0) } ?? "{}"
    let data = Data((json.isEmpty ? "{}" : json).utf8)
    return try JSONDecoder().decode(Req.self, from: data)
}

private func handleSync<Req: Decodable & Sendable, Res: Encodable>(
    _ input: UnsafePointer<CChar>?, _ type: Req.Type, _ body: (Req) throws -> Res
) -> UnsafeMutablePointer<CChar>? {
    do { return makeResponse(try body(try decodeRequest(input, as: Req.self))) }
    catch { return makeError(String(describing: error)) }
}

private func handleAsync<Req: Decodable & Sendable, Res: Encodable & Sendable>(
    _ input: UnsafePointer<CChar>?, _ type: Req.Type, _ body: @escaping @Sendable (Req) async throws -> Res
) -> UnsafeMutablePointer<CChar>? {
    do {
        let req = try decodeRequest(input, as: Req.self)
        let res = try runBlocking { try await body(req) }
        return makeResponse(res)
    } catch {
        return makeError(String(describing: error))
    }
}

/// Bridge a Swift async operation to a synchronous return so it can cross the C
/// ABI. The caller (the WinUI app) invokes bridge functions on a background
/// thread, so blocking here does not stall the UI.
private func runBlocking<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let box = ResultBox<T>()
    Task.detached {
        do { box.value = .success(try await operation()) }
        catch { box.value = .failure(error) }
        semaphore.signal()
    }
    semaphore.wait()
    return try box.value!.get()
}

private final class ResultBox<T>: @unchecked Sendable {
    var value: Result<T, Error>?
}

// MARK: - Exported entry points

@_cdecl("yoru_free")
public func yoru_free(_ ptr: UnsafeMutablePointer<CChar>?) {
    if let ptr { free(ptr) }
}

@_cdecl("yoru_init")
public func yoru_init(_ input: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    handleSync(input, InitReq.self) { req in
        let config = OAuthClientConfig(clientID: req.clientID, redirectURI: req.redirectURI, scope: req.scope)
        BridgeRuntime.shared = BridgeRuntime(service: req.service, config: config)
        return EmptyDTO()
    }
}

@_cdecl("yoru_account_current")
public func yoru_account_current(_ input: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    handleSync(input, EmptyReq.self) { _ in OptionalAccount(try BridgeOps.accountCurrent()) }
}

@_cdecl("yoru_account_list")
public func yoru_account_list(_ input: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    handleSync(input, EmptyReq.self) { _ in try BridgeOps.accountList() }
}

@_cdecl("yoru_account_switch")
public func yoru_account_switch(_ input: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    handleSync(input, DidReq.self) { try BridgeOps.accountSwitch(did: $0.did) }
}

@_cdecl("yoru_account_remove")
public func yoru_account_remove(_ input: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    handleSync(input, DidReq.self) { try BridgeOps.accountRemove(did: $0.did) }
}

@_cdecl("yoru_login_begin")
public func yoru_login_begin(_ input: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    handleAsync(input, HandleReq.self) { try await BridgeOps.loginBegin(handle: $0.handle) }
}

@_cdecl("yoru_login_complete")
public func yoru_login_complete(_ input: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    handleAsync(input, LoginCompleteReq.self) {
        try await BridgeOps.loginComplete(pendingId: $0.pendingId, callbackUrl: $0.callbackUrl)
    }
}

@_cdecl("yoru_timeline_load")
public func yoru_timeline_load(_ input: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    handleAsync(input, CursorReq.self) { try await BridgeOps.timelineLoad(cursor: $0.cursor) }
}

@_cdecl("yoru_author_feed_load")
public func yoru_author_feed_load(_ input: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    handleAsync(input, ActorFeedReq.self) { try await BridgeOps.authorFeedLoad(actor: $0.actor, cursor: $0.cursor) }
}

@_cdecl("yoru_thread_load")
public func yoru_thread_load(_ input: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    handleAsync(input, UriReq.self) { try await BridgeOps.threadLoad(uri: $0.uri) }
}

@_cdecl("yoru_notifications_load")
public func yoru_notifications_load(_ input: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    handleAsync(input, EmptyReq.self) { _ in try await BridgeOps.notificationsLoad() }
}

@_cdecl("yoru_search_load")
public func yoru_search_load(_ input: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    handleAsync(input, SearchReq.self) { try await BridgeOps.searchLoad(filter: $0.filter, cursor: $0.cursor) }
}

@_cdecl("yoru_post_create")
public func yoru_post_create(_ input: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    handleAsync(input, DraftReq.self) { req in try await BridgeOps.postCreate(req.toDraft()) }
}

@_cdecl("yoru_post_like")
public func yoru_post_like(_ input: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    handleAsync(input, LikeReq.self) { try await BridgeOps.like(uri: $0.uri, cid: $0.cid) }
}

@_cdecl("yoru_post_unlike")
public func yoru_post_unlike(_ input: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    handleAsync(input, RecordReq.self) {
        try await BridgeOps.removeRecord(recordUri: $0.recordUri, collection: "app.bsky.feed.like")
    }
}

@_cdecl("yoru_post_repost")
public func yoru_post_repost(_ input: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    handleAsync(input, LikeReq.self) { try await BridgeOps.repost(uri: $0.uri, cid: $0.cid) }
}

@_cdecl("yoru_post_unrepost")
public func yoru_post_unrepost(_ input: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    handleAsync(input, RecordReq.self) {
        try await BridgeOps.removeRecord(recordUri: $0.recordUri, collection: "app.bsky.feed.repost")
    }
}

@_cdecl("yoru_post_permalink")
public func yoru_post_permalink(_ input: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    handleSync(input, PermalinkReq.self) {
        try BridgeOps.permalink(id: $0.id, authorHandle: $0.authorHandle)
    }
}

@_cdecl("yoru_profile_avatar")
public func yoru_profile_avatar(_ input: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    handleAsync(input, EmptyReq.self) { _ in try await BridgeOps.avatar() }
}

@_cdecl("yoru_profile_load")
public func yoru_profile_load(_ input: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    handleAsync(input, ActorReq.self) { try await BridgeOps.profile(actor: $0.actor) }
}

/// Wrapper so `accountCurrent` (which is optional) encodes as `{ "account": ... }`.
private struct OptionalAccount: Encodable {
    let account: AccountDTO?
    init(_ account: AccountDTO?) { self.account = account }
}
#endif
