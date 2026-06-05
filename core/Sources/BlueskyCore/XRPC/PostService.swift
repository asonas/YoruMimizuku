import Foundation

/// Writes posts to the account's PDS over a DPoP-bound channel: uploads image
/// blobs (`com.atproto.repo.uploadBlob`) and creates the post record
/// (`com.atproto.repo.createRecord` / `app.bsky.feed.post`). Mirrors the auth
/// handling of `TimelineService`/`ProfileService`: the `use_dpop_nonce` retry lives
/// in the sender, and a 401 that is not a nonce challenge refreshes via
/// `refresh_token` and retries once. Because a single createPost makes several
/// requests, the latest refreshed tokens are threaded forward and returned so the
/// caller can persist them.
public struct PostService: Sendable {
    private let sender: DPoPRequestSender
    private let metadataResolver: OAuthMetadataResolver
    private let config: OAuthClientConfig

    public init(sender: DPoPRequestSender, metadataResolver: OAuthMetadataResolver, config: OAuthClientConfig) {
        self.sender = sender
        self.metadataResolver = metadataResolver
        self.config = config
    }

    public func uploadBlob(
        pds: URL, issuer: URL, accessToken: String, refreshToken: String?,
        data: Data, mimeType: String
    ) async throws -> (blob: BlobRef, refreshed: TokenResponse?) {
        let url = pds.appendingPathComponent("xrpc/com.atproto.repo.uploadBlob")
        let headers = ["Content-Type": mimeType, "Accept": "application/json"]
        let outcome = try await perform(method: .post, url: url, headers: headers, body: data,
                                        issuer: issuer, accessToken: accessToken, refreshToken: refreshToken)
        let decoded: UploadBlobResponse = try Self.decode(outcome.response)
        return (decoded.blob, outcome.refreshed)
    }

    /// Create a record of any collection (`com.atproto.repo.createRecord`). Used by
    /// the typed `like`/`repost` helpers below; the auth refresh-and-retry is
    /// handled by `perform`. Returns the created record's uri/cid plus refreshed
    /// tokens when a refresh occurred.
    public func createRecord<Record: Encodable & Sendable>(
        pds: URL, issuer: URL, accessToken: String, refreshToken: String?,
        repo: String, collection: String, record: Record
    ) async throws -> (response: CreateRecordResponse, refreshed: TokenResponse?) {
        let request = CreateRecordRequest(repo: repo, collection: collection, record: record)
        let payload = try JSONEncoder().encode(request)
        let url = pds.appendingPathComponent("xrpc/com.atproto.repo.createRecord")
        let outcome = try await perform(
            method: .post, url: url,
            headers: ["Content-Type": "application/json", "Accept": "application/json"],
            body: payload, issuer: issuer, accessToken: accessToken, refreshToken: refreshToken
        )
        let decoded: CreateRecordResponse = try Self.decode(outcome.response)
        return (decoded, outcome.refreshed)
    }

    /// Delete a record (`com.atproto.repo.deleteRecord`), used to undo a like or
    /// repost. Returns refreshed tokens when a 401 triggered a refresh-and-retry.
    @discardableResult
    public func deleteRecord(
        pds: URL, issuer: URL, accessToken: String, refreshToken: String?,
        repo: String, collection: String, rkey: String
    ) async throws -> TokenResponse? {
        let payload = try JSONEncoder().encode(
            DeleteRecordRequest(repo: repo, collection: collection, rkey: rkey)
        )
        let url = pds.appendingPathComponent("xrpc/com.atproto.repo.deleteRecord")
        let outcome = try await perform(
            method: .post, url: url,
            headers: ["Content-Type": "application/json", "Accept": "application/json"],
            body: payload, issuer: issuer, accessToken: accessToken, refreshToken: refreshToken
        )
        guard (200..<300).contains(outcome.response.statusCode) else {
            let errorBody = try? JSONDecoder().decode(XRPCErrorResponse.self, from: outcome.response.body)
            throw XRPCError.requestFailed(status: outcome.response.statusCode, body: errorBody)
        }
        return outcome.refreshed
    }

    /// Like a post: create an `app.bsky.feed.like` whose subject is the post's
    /// strong ref. The returned `uri` is the like record's AT-URI (its rkey is what
    /// `deleteRecord` needs to undo the like).
    public func like(
        pds: URL, issuer: URL, accessToken: String, refreshToken: String?,
        repo: String, subject: StrongRef, createdAt: String = Self.timestamp()
    ) async throws -> (response: CreateRecordResponse, refreshed: TokenResponse?) {
        try await createRecord(
            pds: pds, issuer: issuer, accessToken: accessToken, refreshToken: refreshToken,
            repo: repo, collection: "app.bsky.feed.like",
            record: LikeRecordWrite(subject: subject, createdAt: createdAt)
        )
    }

    /// Repost a post: create an `app.bsky.feed.repost` whose subject is the post's
    /// strong ref. The returned `uri` is the repost record's AT-URI.
    public func repost(
        pds: URL, issuer: URL, accessToken: String, refreshToken: String?,
        repo: String, subject: StrongRef, createdAt: String = Self.timestamp()
    ) async throws -> (response: CreateRecordResponse, refreshed: TokenResponse?) {
        try await createRecord(
            pds: pds, issuer: issuer, accessToken: accessToken, refreshToken: refreshToken,
            repo: repo, collection: "app.bsky.feed.repost",
            record: RepostRecordWrite(subject: subject, createdAt: createdAt)
        )
    }

    /// Create an `app.bsky.feed.post`. Uploads any images first, detects link/tag
    /// facets, resolves `@handle` mentions to DIDs (dropping any that fail), builds
    /// the record, and sends `createRecord`. Threads refreshed tokens across all the
    /// sub-requests and returns the latest so the caller can persist them.
    public func createPost(
        pds: URL, issuer: URL, accessToken: String, refreshToken: String?,
        did: String, text: String, images: [(data: Data, mimeType: String, alt: String)],
        replyParentURI: String?,
        createdAt: String = Self.timestamp()
    ) async throws -> (response: CreateRecordResponse, refreshed: TokenResponse?) {
        var token = accessToken
        var currentRefresh = refreshToken
        var refreshed: TokenResponse? = nil

        func authed(_ method: HTTPMethod, _ url: URL, _ headers: [String: String], _ body: Data?) async throws -> HTTPResponse {
            let outcome = try await perform(method: method, url: url, headers: headers, body: body,
                                            issuer: issuer, accessToken: token, refreshToken: currentRefresh)
            if let tokens = outcome.refreshed {
                refreshed = tokens
                token = tokens.accessToken
                currentRefresh = tokens.refreshToken ?? currentRefresh
            }
            return outcome.response
        }

        // Resolve `@handle` to a DID via getProfile. Returns nil on any failure so the
        // mention facet is dropped and the text is left plain.
        func resolveDID(handle: String) async throws -> String? {
            guard var components = URLComponents(
                url: pds.appendingPathComponent("xrpc/app.bsky.actor.getProfile"), resolvingAgainstBaseURL: false
            ) else { return nil }
            components.queryItems = [URLQueryItem(name: "actor", value: handle)]
            guard let url = components.url else { return nil }
            let response = try await authed(.get, url, ["Accept": "application/json"], nil)
            guard (200..<300).contains(response.statusCode) else { return nil }
            return (try? JSONDecoder().decode(ResolveDIDResponse.self, from: response.body))?.did
        }

        // Build reply refs from a parent at:// URI: getRecord the parent, reuse its
        // conversation root when it is itself a reply, otherwise the parent is the root.
        func fetchReplyRefs(parentURI: String) async throws -> ReplyRefWrite {
            let parts = parentURI.replacingOccurrences(of: "at://", with: "").split(separator: "/", maxSplits: 2)
            guard parts.count == 3 else { throw XRPCError.invalidURL(parentURI) }
            guard var components = URLComponents(
                url: pds.appendingPathComponent("xrpc/com.atproto.repo.getRecord"), resolvingAgainstBaseURL: false
            ) else { throw XRPCError.invalidURL(parentURI) }
            components.queryItems = [
                URLQueryItem(name: "repo", value: String(parts[0])),
                URLQueryItem(name: "collection", value: String(parts[1])),
                URLQueryItem(name: "rkey", value: String(parts[2])),
            ]
            guard let url = components.url else { throw XRPCError.invalidURL(parentURI) }
            let response = try await authed(.get, url, ["Accept": "application/json"], nil)
            let decoded: GetRecordResponse = try Self.decode(response)
            let parentRef = StrongRef(uri: decoded.uri, cid: decoded.cid)
            return ReplyRefWrite(root: decoded.replyRoot ?? parentRef, parent: parentRef)
        }

        // 1. Upload images.
        var imageWrites: [ImageWrite] = []
        for image in images {
            let url = pds.appendingPathComponent("xrpc/com.atproto.repo.uploadBlob")
            let response = try await authed(.post, url,
                                            ["Content-Type": image.mimeType, "Accept": "application/json"],
                                            image.data)
            let decoded: UploadBlobResponse = try Self.decode(response)
            imageWrites.append(ImageWrite(image: decoded.blob, alt: image.alt))
        }

        // 2. Detect facets; resolve mention handles to DIDs.
        var facets: [FacetWrite] = []
        for detected in FacetDetector.detect(text: text) {
            switch detected.feature {
            case .link(let uri):
                facets.append(FacetWrite(byteStart: detected.byteStart, byteEnd: detected.byteEnd, feature: .link(uri: uri)))
            case .tag(let tag):
                facets.append(FacetWrite(byteStart: detected.byteStart, byteEnd: detected.byteEnd, feature: .tag(tag: tag)))
            case .mentionCandidate(let handle):
                if let didValue = try await resolveDID(handle: handle) {
                    facets.append(FacetWrite(byteStart: detected.byteStart, byteEnd: detected.byteEnd, feature: .mention(did: didValue)))
                }
            }
        }
        facets.sort { $0.byteStart < $1.byteStart }

        // 3. Resolve reply refs from the parent URI.
        var reply: ReplyRefWrite? = nil
        if let replyParentURI {
            reply = try await fetchReplyRefs(parentURI: replyParentURI)
        }

        // 4. Build and send the record.
        let embed = imageWrites.isEmpty ? nil : ImagesEmbedWrite(images: imageWrites)
        let record = PostRecordWrite(text: text, createdAt: createdAt, facets: facets, embed: embed, reply: reply)
        let request = CreateRecordRequest(repo: did, collection: "app.bsky.feed.post", record: record)
        let payload = try JSONEncoder().encode(request)
        let url = pds.appendingPathComponent("xrpc/com.atproto.repo.createRecord")
        let response = try await authed(.post, url,
                                        ["Content-Type": "application/json", "Accept": "application/json"],
                                        payload)
        let decoded: CreateRecordResponse = try Self.decode(response)
        return (decoded, refreshed)
    }

    /// ISO8601 timestamp with milliseconds and a `Z` suffix, matching atproto records.
    public static func timestamp(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// One authorized request with a 401→refresh→retry-once. Returns the response
    /// and, when a refresh occurred, the freshly issued tokens.
    func perform(
        method: HTTPMethod, url: URL, headers: [String: String], body: Data?,
        issuer: URL, accessToken: String, refreshToken: String?
    ) async throws -> (response: HTTPResponse, refreshed: TokenResponse?) {
        let response = try await sender.send(method: method, url: url, accessToken: accessToken,
                                             headers: headers, body: body)
        if response.statusCode == 401, !DPoPRequestSender.isNonceChallenge(response), let refreshToken {
            let tokens = try await refresh(issuer: issuer, refreshToken: refreshToken)
            let retried = try await sender.send(method: method, url: url, accessToken: tokens.accessToken,
                                                headers: headers, body: body)
            return (retried, tokens)
        }
        return (response, nil)
    }

    private func refresh(issuer: URL, refreshToken: String) async throws -> TokenResponse {
        let metadata = try await metadataResolver.authorizationServer(issuer: issuer)
        return try await TokenService(sender: sender).requestToken(
            metadata: metadata, config: config, grant: .refresh(refreshToken: refreshToken)
        )
    }

    static func decode<T: Decodable>(_ response: HTTPResponse) throws -> T {
        guard (200..<300).contains(response.statusCode) else {
            let errorBody = try? JSONDecoder().decode(XRPCErrorResponse.self, from: response.body)
            throw XRPCError.requestFailed(status: response.statusCode, body: errorBody)
        }
        do {
            return try JSONDecoder().decode(T.self, from: response.body)
        } catch {
            throw XRPCError.decodingFailed(String(describing: error))
        }
    }
}
