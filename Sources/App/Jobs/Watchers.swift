import APNS
import CXShim
import Foundation
import LemmyApi
import Queues
import Vapor
import Redis

let calendar = Calendar.current
let dateComponents = DateComponents(hour: -24)

struct WatcherJob: AsyncScheduledJob {
    func run(context: QueueContext) async throws {
        let threshold = calendar.date(byAdding: dateComponents, to: Date.now)!
        let communities = try await Community.query(on: context.application.db).with(\.$watchers).all()
        try await withThrowingTaskGroup(of: Bool.self) { group in
            for community in communities {
                group.addTask {
                    var cancellable = Set<AnyCancellable>()
                    let lemmyApi = try! LemmyApi(baseUrl: community.instance)
                    var allPosts = Set<LemmyApi.ApiPost>()
                    for page in 1 ... 5 {
                        let (posts, error) = await withCheckedContinuation { continuation in
                            lemmyApi.getPosts(id: community.localId, page: page, sort: .New, time: .All, limit: 50) { posts, error in
                                continuation.resume(returning: (posts, error))
                            }.store(in: &cancellable)
                        }
                        if let error = error {
                            if case .lemmyError(let message, code: _) = error {
                                print(error, message)
                                if message == "couldnt_find_community" {
                                    try await community.delete(on: context.application.db)
                                    return false
                                }
                            }
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
                        watcherLoop: for watcher in community.watchers {
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
                            try await context.application.redis.setex(redisKey, toJSON: "", expirationInSeconds: 24 * 60 * 60)
                            _ = context.application.apns.send(
                                APNSwiftPayload(alert: .init(title: "New watcher match in \(post.community.name)", subtitle: "\u{201c}\(post.post.name)\u{201d} by \(post.creator.name)", body: post.post.ap_id.absoluteString)),
                                to: watcher.deviceToken
                            )
                        }
                    }
                    return true
                }
            }
            try await group.waitForAll()
        }
    }
}
