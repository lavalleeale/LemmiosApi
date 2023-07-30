import APNS
import Fluent
import FluentPostgresDriver
import NIOSSL
import QueuesRedisDriver
import Vapor
import Queues

// configures your application
public func configure(_ app: Application) async throws {
    // uncomment to serve files from /Public folder
     app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

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
    app.migrations.add(CreateCommunities())
    app.migrations.add(CreateWatchers())
    
    try app.redis.configuration = .init(url: Environment.get("REDIS_HOST") ?? "redis://127.0.0.1:6379")

    try app.queues.use(.redis(url: Environment.get("REDIS_HOST") ?? "redis://127.0.0.1:6379"))

    let decoder = JSONDecoder()
    let formatter1 = DateFormatter()
    formatter1.locale = Locale(identifier: "en_US_POSIX")
    formatter1.timeZone = TimeZone(identifier: "GMT")
    formatter1.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"

    let formatter2 = DateFormatter()
    formatter2.locale = Locale(identifier: "en_US_POSIX")
    formatter2.timeZone = TimeZone(identifier: "GMT")
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
    

    app.queues.scheduleEvery(ReplySchedulerJob(), minutes: 10)
    
    app.queues.schedule(WatcherJob())
        .minutely()
        .at(0)
    
    app.queues.add(RepliesJob())
    
    if let workers = Environment.get("QUEUE_WORKERS"), let workersNum = Int(workers) {
        app.redis.configuration?.pool.maximumConnectionCount = .maximumActiveConnections(workersNum)
        app.queues.configuration.workerCount = .custom(workersNum)
    }
    
    if app.environment.arguments.contains("queues") {
        let pemData = Environment.get("PEM_DATA")
        let pemPath = Environment.get("PEM_PATH")
        app.apns.configuration = try .init(
            authenticationMethod: .jwt(
                key: pemData == nil ? .private(filePath: pemPath!) : .private(pem: pemData!),
                keyIdentifier: "HZY22MR4SG",
                teamIdentifier: "2GA3QKMF6Y"
            ),
            topic: "com.axlav.lemmios",
            environment: app.environment == .development ? .sandbox : .production
        )
    }

    // register routes
    try routes(app)
}

extension Application.Queues {
    func scheduleEvery(_ job: AsyncScheduledJob, minutes: Int) {
        for minuteOffset in stride(from: 0, to: 60, by: minutes) {
            schedule(job).hourly().at(.init(integerLiteral: minuteOffset))
        }
    }
}
