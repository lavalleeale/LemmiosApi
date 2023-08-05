import Fluent
import Vapor

final class Device: Fields, Model, Content {
    static let schema = "devices"
    
    @ID(custom: "deviceToken", generatedBy: .user)
    var id: String?
    
    @Children(for: \.$device)
    var accounts: [User]

    init() { }

    init(deviceToken: String) {
        self.id = deviceToken
    }
}
