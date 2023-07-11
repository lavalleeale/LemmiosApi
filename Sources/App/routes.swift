import Fluent
import Vapor

func routes(_ app: Application) throws {
    app.get { _ async in
        "It works!"
    }
    
    app.get("status") { req async throws in
        let registerPayload = try req.query.decode(InfoPayload.self)
        let user = try await User.query(on: req.db)
            .filter(\.$id == registerPayload.auth)
            .first()
        if let user = user {
            return user
        } else {
            throw Abort(.notFound)
        }
    }

    app.post("register") { req async throws in
        let registerPayload = try req.content.decode(RegisterPayload.self)
        guard let jwt = registerPayload.jwt.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) else {
            return HTTPStatus.badRequest
        }
        
        var response: ClientResponse!
        
        var triesLeft = 10
        repeat {
            if triesLeft != 10 {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            }
            response = try await req.client.get("\(registerPayload.instance)/api/v3/site") { req in
                try req.query.encode(["auth": jwt])
            }
            triesLeft -= 1
        } while triesLeft != 0 && response.status.code == 502
        if response.status.code != 200 {
            return HTTPStatus.internalServerError
        }
        let data = try response.content.decode(SiteInfo.self)
        do {
            try await User(deviceToken: registerPayload.deviceToken, jwt: jwt, username: data.my_user.local_user_view.person.name, instance: registerPayload.instance, lastChecked: .now).create(on: req.db)
        } catch {
            try await User.query(on: req.db)
                .set(\.$id, to: jwt)
                .filter(\.$username == data.my_user.local_user_view.person.name)
                .filter(\.$deviceToken == registerPayload.deviceToken)
                .filter(\.$instance == registerPayload.instance)
                .update()
        }
        return HTTPStatus.ok
    }

    app.post("remove") { req async throws in
        let removePayload = try req.content.decode(RemovePayload.self)
        print(removePayload.jwt)
        try await User.query(on: req.db)
            .filter(\.$id == removePayload.jwt)
            .delete()
        return ""
    }
}

struct InfoPayload: Codable {
    let auth: String
}

struct SiteInfo: Codable {
    var my_user: LocalUserView
}

struct LocalUserView: Codable {
    var local_user_view: ApiUser
}

struct ApiUser: Codable {
    var person: UserData
}

struct RegisterPayload: Content {
    let jwt: String
    let instance: String
    let deviceToken: String
}

struct RemovePayload: Content {
    let jwt: String
}
