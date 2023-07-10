import Fluent

struct CreateUser: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("users")
            .field("jwt", .string, .required)
            .unique(on: "jwt")
            .field("deviceToken", .string, .required)
            .field("instance", .string, .required)
            .field("lastChecked", .datetime, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("users").delete()
    }
}
