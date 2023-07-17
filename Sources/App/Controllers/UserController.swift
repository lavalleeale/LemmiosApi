import Foundation
import Vapor
import Fluent
import LemmyApi
import CXShim

struct UserController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let todos = routes.grouped("user")
        todos.post("register", use: register)
        todos.post("remove", use: remove)
    }

    func register(req: Request) async throws -> HTTPStatus {
        var cancellable = Set<AnyCancellable>()
        let registerPayload = try req.content.decode(RegisterPayload.self)
        guard let jwt = registerPayload.jwt.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) else {
            return HTTPStatus.badRequest
        }
        
        let lemmyApi = try! LemmyApi(baseUrl: registerPayload.instance)
        lemmyApi.setJwt(jwt: jwt)
        
        let (response, error) = await withCheckedContinuation { continuation in
            lemmyApi.getSiteInfo { siteInfo, error in
                continuation.resume(returning: (siteInfo, error))
            }.store(in: &cancellable)
        }
        if let person = response?.my_user?.local_user_view.person {
            do {
                try await User(deviceToken: registerPayload.deviceToken, jwt: jwt, username: person.name, instance: registerPayload.instance, lastChecked: .now).create(on: req.db)
                req.logger.info("Registered \(person.actor_id)")
            } catch {
                try await User.query(on: req.db)
                    .set(\.$id, to: jwt)
                    .filter(\.$username == person.name)
                    .filter(\.$deviceToken == registerPayload.deviceToken)
                    .filter(\.$instance == registerPayload.instance)
                    .update()
                req.logger.info("Updated \(person.actor_id)")
            }
            return HTTPStatus.ok
        }
        return HTTPStatus.unauthorized
    }

    func remove(req: Request) async throws -> HTTPStatus {
        let removePayload = try req.content.decode(RemovePayload.self)
        try await User.query(on: req.db)
            .filter(\.$id == removePayload.jwt)
            .delete()
        return HTTPStatus.ok
    }
}
