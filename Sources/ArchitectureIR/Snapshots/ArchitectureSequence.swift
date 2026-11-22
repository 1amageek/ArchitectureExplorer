import Foundation

/// A declared interaction scenario resolved against the architecture in one captured snapshot.
public struct ArchitectureSequence: Codable, Sendable, Equatable {
  public struct Declaration: Codable, Sendable, Equatable {
    public let path: String
    public let line: Int
    public let text: String

    public init(path: String, line: Int, text: String) {
      self.path = path
      self.line = line
      self.text = text
    }
  }

  public struct Citation: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable { case recorded, stale, unavailable }
    public let path: String
    public let line: Int
    public let digest: String
    public let status: Status
    public let excerpt: String?

    public init(path: String, line: Int, digest: String, status: Status, excerpt: String? = nil) {
      self.path = path
      self.line = line
      self.digest = digest
      self.status = status
      self.excerpt = excerpt
    }
  }

  public struct Participant: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let entryID: String?

    public init(id: String, name: String, entryID: String?) {
      self.id = id
      self.name = name
      self.entryID = entryID
    }
  }

  public struct Message: Codable, Sendable, Equatable {
    public let source: String
    public let target: String
    public let label: String
    public let reply: Bool
    public let declaration: Declaration
    public let relationship: Declaration
    public let citations: [Citation]

    public init(source: String, target: String, label: String, reply: Bool, declaration: Declaration,
      relationship: Declaration, citations: [Citation]) {
      self.source = source
      self.target = target
      self.label = label
      self.reply = reply
      self.declaration = declaration
      self.relationship = relationship
      self.citations = citations
    }
  }

  public let key: String
  public let title: String
  public let subjectID: String?
  public let participants: [Participant]
  public let requirements: [String]
  public let declaration: Declaration
  public let messages: [Message]

  public init(key: String, title: String, subjectID: String?, participants: [Participant],
    requirements: [String], declaration: Declaration, messages: [Message]) {
    self.key = key
    self.title = title
    self.subjectID = subjectID
    self.participants = participants
    self.requirements = requirements
    self.declaration = declaration
    self.messages = messages
  }
}
