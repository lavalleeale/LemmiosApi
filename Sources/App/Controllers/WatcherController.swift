import Foundation
import Vapor
import LemmyApi
import CXShim

struct WatcherController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let watchers = routes.grouped("watcher")
        watchers.post("create", use: create)
        watchers.post("delete", use: delete)
    }
    
    func delete(req: Request) async throws -> HTTPStatus {
        let deletePayload = try req.content.decode(DeleteWatcherPayload.self)
        try await Watcher.query(on: req.db)
            .filter(\.$id, .equal, deletePayload.id)
            .delete()
        return .ok
    }
    
    func create(req: Request) async throws -> Watcher {
        var cancellable: AnyCancellable?
        _ = cancellable
        let watcherPayload = try req.content.decode(WatcherPayload.self)
        let lemmyApi = try LemmyApi(baseUrl: watcherPayload.instance)
        let (communityInfo, error) = await withCheckedContinuation { continuation in
            cancellable = lemmyApi.getCommunity(name: watcherPayload.community) { community, error in
                continuation.resume(returning: (community, error))
            }
        }
        if let communityInfo = communityInfo {
            var community = try await Community.query(on: req.db)
                .filter(\.$instance, .equal, lemmyApi.baseUrl)
                .filter(\.$localId, .equal, communityInfo.community_view.id)
                .first()
            if community == nil {
                community = Community(instance: lemmyApi.baseUrl, localId: communityInfo.community_view.id)
                try await community!.create(on: req.db)
            }
            let watcher = Watcher(deviceToken: watcherPayload.deviceToken, upvotes: watcherPayload.upvotes, author: watcherPayload.author, keywords: watcherPayload.keywords, communityId: community!.id!)
            try await watcher.create(on: req.db)
            return watcher
        } else {
            if case let .lemmyError(message: message, code: _) = error {
                throw Abort(.badRequest, reason: message)
            }
            throw Abort(.internalServerError, reason: "Unknown")
        }
    }
}

struct DeleteWatcherPayload: Content {
    let id: UUID
}

struct WatcherPayload: Content {
    let keywords: String
    let deviceToken: String
    let author: String
    let upvotes: Int64
    let community: String
    let instance: String
}
