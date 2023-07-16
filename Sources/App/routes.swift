import Combine
import Fluent
import LemmyApi
import Vapor

var cancellable = Set<AnyCancellable>()

func routes(_ app: Application) throws {
    app.get { _ async in
        "It works!"
    }
    
    app.post("register") { req async throws in
        req.redirect(to: "/user/register", redirectType: .permanentPost)
    }
    
    app.post("remove") { req async throws in
        req.redirect(to: "/user/remove", redirectType: .permanentPost)
    }

    try app.register(collection: UserController())
}

struct InfoPayload: Codable {
    let auth: String
}

struct RegisterPayload: Content {
    let jwt: String
    let instance: String
    let deviceToken: String
}

struct RemovePayload: Content {
    let jwt: String
}
