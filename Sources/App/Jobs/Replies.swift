import APNS
import Foundation
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
                    let countResponse = try await context.application.client.get("\(user.instance)/api/v3/user/unread_count?auth=\(user.id!)")
                    switch countResponse.status {
                    case .badRequest:
                        if let errorData = try? countResponse.content.decode(ErrorData.self), errorData.error == "not_logged_in" {
                            print(errorData, user.username)
                            try await user.delete(on: context.application.db)
                        }
                    case .ok:
                        guard let replyCount = try? countResponse.content.decode(UnreadCount.self) else {
                            return false
                        }
                        let total = replyCount.replies + replyCount.private_messages
                        if total != 0 {
                            _ = context.application.apns.send(APNSwiftPayload(badge: total), to: user.deviceToken)
                        }
                        if replyCount.replies != 0 {
                            let repliesResponse = try await context.application.client.get("\(user.instance)/api/v3/user/replies?auth=\(user.id!)")
                            guard repliesResponse.status == .ok else {
                                return false
                            }
                            if let replies = try? repliesResponse.content.decode(Replies.self).replies.filter({ $0.comment.published > user.lastChecked }) {
                                for reply in replies {
                                    _ = context.application.apns.send(
                                        APNSwiftPayload(alert: .init(title: "New reply from \(reply.creator.name)", subtitle: reply.comment.content)),
                                        to: user.deviceToken
                                    )
                                }
                            }
                        }
                        if replyCount.private_messages != 0 {
                            let messagesResponse = try await context.application.client.get("\(user.instance)/api/v3/private_message/list?auth=\(user.id!)")
                            guard messagesResponse.status == .ok else {
                                return false
                            }
                            if let messages = try? messagesResponse.content.decode(Messages.self).private_messages.filter({ $0.private_message.published > user.lastChecked }) {
                                for message in messages {
                                    _ = context.application.apns.send(
                                        APNSwiftPayload(alert: .init(title: "New message from \(message.creator.name)", subtitle: message.private_message.content)),
                                        to: user.deviceToken
                                    )
                                }
                            }
                        }
                    default:
                        return false
                    }
                    return true
                }
            }
            try await group.waitForAll()
        }
        print(Date.now)
    }
}

struct ErrorData: Codable {
    let error: String
}

struct UnreadCount: Codable {
    let replies: Int
    let mentions: Int
    let private_messages: Int
}

struct Replies: Codable {
    let replies: [Reply]
}

struct Reply: Codable {
    let comment: Comment
    let creator: UserData
}

struct Comment: Codable {
    let content: String
    let published: Date
}

struct UserData: Codable {
    let name: String
}

struct Messages: Codable {
    let private_messages: [Message]
}

struct Message: Codable {
    let creator: UserData
    var private_message: MessageContent
}

struct MessageContent: Codable {
    let content: String
    let published: Date
}
