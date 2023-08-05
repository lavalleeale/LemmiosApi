import Fluent

struct CreateDevices: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(Device.schema)
            .field("deviceToken", .string, .required, .identifier(auto: false))
            .create()
        let users = try await User.query(on: database)
            .all()
        for user in Set(users.map { $0.$device.id }) {
            try await Device(deviceToken: user).create(on: database)
        }
        try await database.schema(User.schema)
            .foreignKey("deviceToken", references: Device.schema, "deviceToken")
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema(User.schema)
            .deleteForeignKey(name: "fk:users.deviceToken+users.deviceToken")
            .update()
        try await database.schema(Device.schema).delete()
    }
}
