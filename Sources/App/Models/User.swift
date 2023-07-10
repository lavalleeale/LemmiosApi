import Fluent
import Vapor

final class User: Fields, Model {
    static let schema = "users"
    
    @ID(custom: "deviceToken", generatedBy: .user)
    var id: String?

    @Field(key: "jwt")
    var jwt: String
    
    @Field(key: "instance")
    var instance: String
    
    @Field(key: "lastChecked")
    var lastChecked: Date

    init() { }

    init(deviceToken: String, jwt: String, instance: String, lastChecked: Date) {
        self.id = deviceToken
        self.jwt = jwt
        self.instance = instance
        self.lastChecked = lastChecked
    }
}
