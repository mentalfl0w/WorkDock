import Foundation

/// Per-document summary shown in lists (the row shape).
public struct DocumentSummary: Codable, Hashable, Sendable {
    public let id: String          // UNID
    public let noteID: String
    public let title: String
    public let publisher: String  // 来文机关
    public let publishedAt: String
    public let docMark: String    // 文号
    public let urgency: String

    public init(id: String, noteID: String, title: String, publisher: String,
                publishedAt: String, docMark: String, urgency: String) {
        self.id = id; self.noteID = noteID; self.title = title
        self.publisher = publisher; self.publishedAt = publishedAt
        self.docMark = docMark; self.urgency = urgency
    }
}

/// Full document detail (the detail-view shape).
public struct DocumentDetail: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let docMark: String
    public let publisher: String
    public let publishNote: String
    public let publicAttribute: String
    public let priority: String
    public let database: String
    public let key: String

    public init(id: String, title: String, docMark: String, publisher: String,
                publishNote: String, publicAttribute: String, priority: String,
                database: String, key: String) {
        self.id = id; self.title = title; self.docMark = docMark
        self.publisher = publisher; self.publishNote = publishNote
        self.publicAttribute = publicAttribute; self.priority = priority
        self.database = database; self.key = key
    }
}

/// Attachment metadata for download links.
public struct Attachment: Codable, Hashable, Sendable {
    public let name: String       // Display title (e.g. "公文正文")
    public let fileName: String   // Real filename with extension (e.g. "xxx.doc")
    public let url: URL
    /// Display name with extension: e.g. "公文正文.doc"
    public var displayName: String {
        let ext = (fileName as NSString).pathExtension
        return ext.isEmpty ? name : "\(name).\(ext)"
    }
    /// Save name: display name + extension, e.g. "公文正文.doc"
    public var saveName: String { displayName }
    public init(name: String, fileName: String, url: URL) {
        self.name = name; self.fileName = fileName; self.url = url
    }
}

/// Authenticated user profile from the platform.
public struct UserProfile: Codable, Hashable, Sendable {
    public let userName: String
    public let userNameTitle: String
    public let unit: String
    public let unitID: String

    public init(userName: String, userNameTitle: String, unit: String, unitID: String) {
        self.userName = userName; self.userNameTitle = userNameTitle
        self.unit = unit; self.unitID = unitID
    }
}
