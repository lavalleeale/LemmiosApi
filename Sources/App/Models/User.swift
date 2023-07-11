import Fluent
import Vapor

final class User: Fields, Model, Content {
    static let schema = "users"
    
    @ID(custom: "jwt", generatedBy: .user)
    var id: String?
    
    @Field(key: "username")
    var username: String

    @Field(key: "deviceToken")
    var deviceToken: String
    
    @Field(key: "instance")
    var instance: String
    
    @Field(key: "lastChecked")
    var lastChecked: Date

    init() { }

    init(deviceToken: String, jwt: String, username: String, instance: String, lastChecked: Date) {
        self.id = jwt
        self.deviceToken = deviceToken
        self.username = username
        self.instance = instance
        self.lastChecked = lastChecked
    }
}
