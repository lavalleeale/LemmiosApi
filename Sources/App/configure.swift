import APNS
import Fluent
import FluentPostgresDriver
import NIOSSL
import Vapor
import QueuesRedisDriver


// configures your application
public func configure(_ app: Application) async throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    app.databases.use(.postgres(configuration: SQLPostgresConfiguration(
        hostname: Environment.get("DATABASE_HOST") ?? "localhost",
        port: Environment.get("DATABASE_PORT").flatMap(Int.init(_:)) ?? SQLPostgresConfiguration.ianaPortNumber,
        username: Environment.get("DATABASE_USERNAME") ?? "vapor_username",
        password: Environment.get("DATABASE_PASSWORD") ?? "vapor_password",
        database: Environment.get("DATABASE_NAME") ?? "vapor_database",
        tls: .prefer(try .init(configuration: .clientDefault))
    )
    ), as: .psql)

    app.migrations.add(CreateUser())
    
    try app.queues.use(.redis(url: Environment.get("REDIS_HOST") ?? "redis://127.0.0.1:6379"))
    
    let decoder = JSONDecoder()
    let formatter1 = DateFormatter()
    formatter1.locale = Locale(identifier: "en_US_POSIX")
    formatter1.timeZone = TimeZone(identifier:"GMT")
    formatter1.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"

    let formatter2 = DateFormatter()
    formatter2.locale = Locale(identifier: "en_US_POSIX")
    formatter2.timeZone = TimeZone(identifier:"GMT")
    formatter2.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    decoder.dateDecodingStrategy = .custom { decoder -> Date in
        let container = try decoder.singleValueContainer()
        let dateStr = try container.decode(String.self)
        var date: Date?
        if dateStr.contains(".") {
            date = formatter1.date(from: dateStr)
        } else {
            date = formatter2.date(from: dateStr)
        }
        guard let date_ = date else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateStr)")
        }
        return date_
    }
    
    ContentConfiguration.global.use(decoder: decoder, for: .json)
    
    app.queues.schedule(ReplyJob())
        .minutely()
        .at(49)

    let pemData = Environment.get("PEM_DATA")
    app.apns.configuration = try .init(
        authenticationMethod: .jwt(
            key: pemData == nil ? .private(filePath: "/tmp/test.p8") : .private(pem: pemData!),
            keyIdentifier: "HZY22MR4SG",
            teamIdentifier: "2GA3QKMF6Y"
        ),
        topic: "com.axlav.lemmios",
        environment: .sandbox
    )

    // register routes
    try routes(app)
}
