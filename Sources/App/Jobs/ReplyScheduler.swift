import APNS
import CXShim
import Foundation
import LemmyApi
import Queues
import RediStack
import Vapor

struct ReplySchedulerJob: AsyncScheduledJob {
    func run(context: QueueContext) async throws {
        let totalTime = Double(context.application.config?.reply_poll ?? 10) * 60 - 30
        let devices = try await Device.query(on: context.application.db).with(\.$accounts).all()
        for device in devices {
            try await context.application.redis.setex(RedisKey(rawValue: "device:\(device.id!)")!, toJSON: 0, expirationInSeconds: 15 * 60)
        }
        let users = devices.flatMap { $0.accounts }
        for instance in Dictionary(grouping: users, by: { $0.instance }) {
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
