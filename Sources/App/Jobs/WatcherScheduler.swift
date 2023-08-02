import APNS
import CXShim
import Foundation
import LemmyApi
import Queues
import Vapor

struct WatcherSchedulerJob: AsyncScheduledJob {
    func run(context: QueueContext) async throws {
        let totalTime = Double(context.application.config?.reply_poll ?? 10) * 60 - 30
        let communities = try await Community.query(on: context.application.db).with(\.$watchers).all()
        let maxOffset = communities.count
        for instance in Dictionary(grouping: communities, by: { $0.instance }) {
            for community in instance.value.enumerated() {
                if community.element.watchers.isEmpty {
                    try await community.element.delete(on: context.application.db)
                } else {
                    let targetTime = Date.now + TimeInterval(community.offset % maxOffset) * totalTime / Double(maxOffset)
                    try await context.queue.dispatch(
                        WatchersJob.self, community.element,
                        delayUntil: targetTime,
                        id: JobIdentifier(string: "\(community.element.localId)@\(community.element.instance)@\(targetTime)")
                    )
                }
            }
        }
    }
}
