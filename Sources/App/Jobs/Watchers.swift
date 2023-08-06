import APNS
import CXShim
import Foundation
import LemmyApi
import Queues
import Redis
import Vapor

let calendar = Calendar.current
let dateComponents = DateComponents(hour: -24)

struct WatchersJob: AsyncJob {
    typealias Payload = Community
    func dequeue(_ context: Queues.QueueContext, _ community: Community) async throws {
        let threshold = calendar.date(byAdding: dateComponents, to: Date.now)!
        var cancellable = Set<AnyCancellable>()
        let lemmyApi = try! LemmyApi(baseUrl: community.instance)
        var allPosts = Set<LemmyApi.PostView>()
        for page in 1 ... 5 {
            let (posts, error) = await withCheckedContinuation { continuation in
                lemmyApi.getPosts(id: community.localId, page: page, sort: .New, time: .All, limit: 50) { posts, error in
                    continuation.resume(returning: (posts, error))
                }.store(in: &cancellable)
            }
            if let error = error {
                if case .lemmyError(let message, code: _) = error {
                    context.application.logger.error("Failed to get community \(community.id!)@\(community.instance) with error \(message)")
                    if message == "couldnt_find_community" {
                        try await community.delete(on: context.application.db)
                    }
                }
                return
            } else if let posts = posts {
                for post in posts.posts {
                    if post.counts.published < threshold {
                        break
                    }
                    allPosts.insert(post)
                }
                if allPosts.count < page * 50 {
                    break
                }
            }
        }
        for post in allPosts {
        watcherLoop: for watcher in try await community.$watchers.get(on: context.application.db) {
                let redisKey = RedisKey("\(watcher.id):\(post.post.id)")
                do {
                    let newValue = try await context.application.redis.get(redisKey, asJSON: String.self)
                    if newValue != nil {
                        continue
                    }
                } catch {
                    continue
                }
                if post.counts.published < watcher.createdAt! {
                    continue
                }

                if post.counts.score < watcher.upvotes {
                    continue
                }

                if watcher.author != "" && watcher.author != post.creator.name {
                    continue
                }

                let keywords = watcher.keywords.components(separatedBy: " ")
                for keyword in keywords.filter({ $0 != "" }) {
                    if !post.post.name.contains(keyword) {
                        continue watcherLoop
                    }
                }
                watcher.hits += 1
                try await watcher.update(on: context.application.db)
                try await context.application.redis.setex(redisKey, toJSON: "", expirationInSeconds: 24 * 60 * 60)
                let notificationPayload = APNSwiftPayload(alert: .init(title: "New watcher match in \(post.community.name)", subtitle: "\u{201c}\(post.post.name)\u{201d} by \(post.creator.name)", body: post.post.ap_id.absoluteString))
                _ = context.application.apns.send(
                    Notification(aps: notificationPayload, url: post.post.ap_id),
                    to: watcher.deviceToken
                )
            }
        }
    }
}
