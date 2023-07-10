import APNS
import Foundation
import Queues
import Vapor

struct ReplyJob: AsyncScheduledJob {
    func run(context: QueueContext) async throws {
        let users = try await User.query(on: context.application.db).all()
        print(users.count)
        await withTaskGroup(of: Bool.self) { group in
            for user in users {
                print(user.deviceToken)
                group.addTask {
                    do {
                        let response = try await context.application.client.get("\(user.instance)/api/v3/user/replies?auth=\(user.id!)")
                        switch response.status {
                        case .badRequest:
                            try await user.delete(on: context.application.db)
                        case .ok:
                            let replies = try response.content.decode(Replies.self).replies.filter { $0.comment.published > user.lastChecked }
                            if replies.isEmpty {
                                return false
                            }
                            user.lastChecked = .now
                            try await user.update(on: context.application.db)
                            let response = try await context.application.client.get("\(user.instance)/api/v3/user/unread_count?auth=\(user.id!)")
                            if let replyCount = try? response.content.decode(UnreadCount.self).replies {
                                _ = context.application.apns.send(APNSwiftPayload(badge: replyCount), to: user.deviceToken)
                            }
                            for reply in replies {
                                _ = context.application.apns.send(
                                    APNSwiftPayload(alert: .init(title: "New reply from \(reply.creator.name)", subtitle: reply.comment.content)),
                                    to: user.deviceToken
                                )
                            }
                        default:
                            return false
                        }
                    } catch {
                        print(error)
                    }
                    return true
                }
            }
            await group.waitForAll()
        }
    }
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
    let id: Int
}

struct UserData: Codable {
    let name: String
    let id: Int
}
