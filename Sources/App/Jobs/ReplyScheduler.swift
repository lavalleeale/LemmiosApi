import APNS
import CXShim
import Foundation
import LemmyApi
import Queues
import Vapor

struct ReplySchedulerJob: AsyncScheduledJob {
    func run(context: QueueContext) async throws {
        let totalTime = Double(context.application.config?.reply_poll ?? 10) * 60 - 30
        let users = try await User.query(on: context.application.db).all()
        for instance in Dictionary(grouping: users, by: {$0.instance}) {
            if Environment.get("SKIP_INSTANCES")?.contains(instance.key) != true {
                context.application.logger.info("Checking replies for \(instance.value.count) users in \(instance.key)")
                let maxOffset = instance.value.count
                for user in instance.value.enumerated() {
                    let targetTime = Date.now + TimeInterval(user.offset % maxOffset) * totalTime / Double(maxOffset)
                    try await context.queue.dispatch(
                        RepliesJob.self, user.element,
                        delayUntil: targetTime,
                        id: JobIdentifier(string: "\(user.element.username)@\(user.element.instance)@\(targetTime)")
                    )
                }
            }
        }
    }
}
