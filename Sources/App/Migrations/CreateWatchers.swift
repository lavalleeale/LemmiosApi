import Fluent

struct CreateWatchers: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("watchers")
            .id()
            .field("community_id", .uuid, .required, .references("communities", "id"))
            .field("deviceToken", .string, .required)
            .field("upvotes", .int64)
            .field("hits", .int64)
            .field("author", .string, .required)
            .field("keywords", .string, .required)
            .field("created_at", .datetime, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("watchers").delete()
    }
}
