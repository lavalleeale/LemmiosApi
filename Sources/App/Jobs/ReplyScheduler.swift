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
        let maxOffset = users.count
        for user in users.enumerated() {
            if Environment.get("SKIP_INSTANCES")?.contains(user.element.instance) != true {
                try await context.queue.dispatch(RepliesJob.self, user.element, delayUntil: Date.now + TimeInterval(user.offset % maxOffset) * 600.0 / Double(maxOffset))                
            }
        }
    }
}
