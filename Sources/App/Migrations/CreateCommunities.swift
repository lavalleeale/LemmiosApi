import Fluent

struct CreateCommunities: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(Community.schema)
            .id()
            .field("instance", .string, .required)
            .field("localId", .int32, .required)
            .unique(on: "instance", "localId")
            .create()

    }

    func revert(on database: Database) async throws {
        try await database.schema(Community.schema).delete()
    }
}
