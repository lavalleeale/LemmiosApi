import APNS
import CXShim
import Foundation
import LemmyApi
import Queues
import RediStack
import Vapor

struct RepliesJob: AsyncJob {
    typealias Payload = User

    func dequeue(_ context: Queues.QueueContext, _ payload: User) async throws {
        let getRepliesTask = Task {
            var cancellable = Set<AnyCancellable>()
            let lemmyApi = try! LemmyApi(baseUrl: payload.instance)
            lemmyApi.setJwt(jwt: payload.id!)
            let (countResponse, error) = await withCheckedContinuation { continuation in
                lemmyApi.getUnreadCount { unread, error in
                    continuation.resume(returning: (unread, error))
                }.store(in: &cancellable)
            }
            if let error = error {
                if case .lemmyError(let message, code: _) = error {
                    context.application.logger.error("Failed to get replies for \(payload.username) with error \(message)")
//                    try await user.delete(on: context.application.db)
                } else {
                    context.application.logger.error("Failed to get replies for \(payload.username) with unknown error \(error)")
                }
            } else if let countResponse = countResponse {
                let total = countResponse.replies + countResponse.private_messages
                if total != 0 {
                    let key = RedisKey(rawValue: "device:\(payload.$device.id)")!
                    let previousBadge = try await context.application.redis.get(key, asJSON: Int.self) ?? 0
                    let notifCount = previousBadge + total
                    _ = context.application.apns.send(
                        APNSwiftPayload(badge: notifCount),
                        to: payload.$device.id
                    )
                    try await context.application.redis.setex(key, toJSON: notifCount, expirationInSeconds: 15 * 60)
                }
                if countResponse.replies != 0 {
                    let (repliesResponse, error) = await withCheckedContinuation { continuation in
                        lemmyApi.getReplies(page: 1, sort: LemmyApi.Sort.New, unread: true) { replies, error in
                            continuation.resume(returning: (replies, error))
                        }.store(in: &cancellable)
                    }
                    guard let repliesResponse = repliesResponse else {
                        return
                    }
                    let replies = repliesResponse.replies.filter { $0.counts.published > payload.lastChecked }
                    for reply in replies {
                        let notificationPayload = APNSwiftPayload(alert: .init(title: "New reply from \(reply.creator.name)", subtitle: reply.comment.content))
                        _ = context.application.apns.send(
                            Notification(aps: notificationPayload, url: reply.comment.ap_id),
                            to: payload.$device.id
                        )
                    }
                }
                if countResponse.private_messages != 0 {
                    let (messagesResponse, error) = await withCheckedContinuation { continuation in
                        lemmyApi.getMessages(page: 1, sort: LemmyApi.Sort.New, unread: true) { messages, error in
                            continuation.resume(returning: (messages, error))
                        }.store(in: &cancellable)
                    }
                    guard let messagesResponse = messagesResponse else {
                        return
                    }
                    let messages = messagesResponse.private_messages.filter { $0.private_message.published > payload.lastChecked }
                    for message in messages {
                        let notificationPayload = APNSwiftPayload(alert: .init(title: "New message from \(message.creator.name)", subtitle: message.private_message.content))
                        _ = context.application.apns.send(
                            Notification(aps: notificationPayload, url: message.private_message.ap_id),
                            to: payload.$device.id,
                            loggerConfig: .none
                        )
                    }
                }
            }
        }

        let timeoutTask = Task {
            let timeout = context.application.config?.reply_timeout ?? 5
            try await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000_000)
            getRepliesTask.cancel()
        }

        try await getRepliesTask.value
        timeoutTask.cancel()
        try await User.query(on: context.application.db)
            .filter(\.$id, .equal, payload.id!)
            .set(\.$lastChecked, to: .now)
            .update()
    }
}

struct Notification: APNSwiftNotification {
    let aps: APNSwift.APNSwiftPayload
    let url: URL
}
