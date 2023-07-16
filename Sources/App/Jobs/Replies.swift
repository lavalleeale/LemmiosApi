import APNS
import Combine
import Foundation
import LemmyApi
import Queues
import Vapor

struct ReplyJob: AsyncScheduledJob {
    func run(context: QueueContext) async throws {
        let users = try await User.query(on: context.application.db).all()
        try await User.query(on: context.application.db)
            .set(\.$lastChecked, to: .now)
            .update()
        print(users.count)
        try await withThrowingTaskGroup(of: Bool.self) { group in
            for user in users {
                print(user.username)
                group.addTask {
                    var cancellable = Set<AnyCancellable>()
                    let lemmyApi = try! LemmyApi(baseUrl: user.instance)
                    lemmyApi.setJwt(jwt: user.id!)
                    let (countResponse, error) = await withCheckedContinuation { continuation in
                        lemmyApi.getUnreadCount { unread, error in
                            continuation.resume(returning: (unread, error))
                        }.store(in: &cancellable)
                    }
                    if let error = error {
                        if case .lemmyError(let message, code: _) = error {
                            print(error, message)
//                            try await user.delete(on: context.application.db)
                        }
                    } else if let countResponse = countResponse {
                        let total = countResponse.replies + countResponse.private_messages
                        if total != 0 {
                            _ = context.application.apns.send(APNSwiftPayload(badge: total), to: user.deviceToken)
                        }
                        if countResponse.replies != 0 {
                            let (repliesResponse, error) = await withCheckedContinuation { continuation in
                                lemmyApi.getReplies(page: 1, sort: LemmyApi.Sort.New, unread: true) { replies, error in
                                    continuation.resume(returning: (replies, error))
                                }.store(in: &cancellable)
                            }
                            guard let repliesResponse = repliesResponse else {
                                return false
                            }
                            let replies = repliesResponse.replies.filter { $0.counts.published > user.lastChecked }
                            for reply in replies {
                                _ = context.application.apns.send(
                                    APNSwiftPayload(alert: .init(title: "New reply from \(reply.creator.name)", subtitle: reply.comment.content)),
                                    to: user.deviceToken
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
                                return false
                            }
                            let messages = messagesResponse.private_messages.filter { $0.private_message.published > user.lastChecked }
                            for message in messages {
                                _ = context.application.apns.send(
                                    APNSwiftPayload(alert: .init(title: "New message from \(message.creator.name)", subtitle: message.private_message.content)),
                                    to: user.deviceToken
                                )
                            }
                        }
                    }

                    return true
                }
            }
            try await group.waitForAll()
        }
        print(Date.now)
    }
}
