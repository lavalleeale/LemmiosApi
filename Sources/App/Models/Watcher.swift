import Fluent
import Vapor

final class Watcher: Fields, Model, Content {
    static let schema = "watchers"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "community_id")
    var community: Community

    @Field(key: "deviceToken")
    var deviceToken: String

    @Field(key: "upvotes")
    var upvotes: Int64

    @Field(key: "hits")
    var hits: Int64

    @Field(key: "author")
    var author: String

    @Field(key: "keywords")
    var keywords: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(deviceToken: String, upvotes: Int64, author: String, keywords: String, communityId: Community.IDValue) {
        self.$community.id = communityId
        self.deviceToken = deviceToken
        self.upvotes = upvotes
        self.hits = 0
        self.author = author
        self.keywords = keywords
    }
}
