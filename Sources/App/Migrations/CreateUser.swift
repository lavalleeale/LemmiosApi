import Fluent

struct CreateUser: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(User.schema)
            .field("jwt", .string, .required, .identifier(auto: false))
            .field("deviceToken", .string, .required)
            .field("instance", .string, .required)
            .field("username", .string, .required)
            .field("lastChecked", .datetime, .required)
            .unique(on: "deviceToken", "instance", "username")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(User.schema).delete()
    }
}
