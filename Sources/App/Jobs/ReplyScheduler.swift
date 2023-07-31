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
        for instance in Dictionary(grouping: users, by: {$0.instance}) {
            if Environment.get("SKIP_INSTANCES")?.contains(instance.key) != true {
                context.application.logger.info("Checking replies for \(instance.value.count) users in \(instance.key)")
                let maxOffset = instance.value.count
                for user in instance.value.enumerated() {
                    try await context.queue.dispatch(RepliesJob.self, user.element, delayUntil: Date.now + TimeInterval(user.offset % maxOffset) * 570.0 / Double(maxOffset))
                }
            }
        }
    }
}
