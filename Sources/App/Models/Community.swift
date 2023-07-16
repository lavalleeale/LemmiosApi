import Fluent
import Vapor

final class Community: Fields, Model, Content {
    static let schema = "communities"
    
    @ID(key: .id)
    var id: UUID?
    
    @Children(for: \.$community)
    var watchers: [Watcher]
    
    @Field(key: "localId")
    var localId: Int
    
    @Field(key: "instance")
    var instance: String

    init() { }

    init(instance: String, localId: Int) {
        self.localId = localId
        self.instance = instance
    }
}
