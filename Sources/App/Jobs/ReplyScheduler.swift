import APNS
import CXShim
import Foundation
import LemmyApi
import Queues
import Vapor

struct ReplySchedulerJob: AsyncScheduledJob {
    func run(context: QueueContext) async throws {
        let users = try await User.query(on: context.application.db).all()
        try await User.query(on: context.application.db)
            .set(\.$lastChecked, to: .now)
            .update()
        context.application.logger.info("Checking replies for \(users.count) users")
        for user in users.enumerated() {
            try await context.queue.dispatch(RepliesJob.self, user.element, delayUntil: Date.now + TimeInterval(user.offset % 110))
        }
    }
}
