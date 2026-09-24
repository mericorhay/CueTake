import Foundation

/// What a creator pastes when posting the finished video: a cover line, a title, the text and
/// hashtags for each platform, and an honest read of the opening seconds.
public struct PostKit: Hashable, Sendable, Codable {
    public struct Post: Hashable, Sendable, Codable, Identifiable {
        public var id: String { platform }
        /// `tiktok`, `instagram`, `youtube` or `linkedin`.
        public var platform: String
        public var text: String
        /// Without the #.
        public var hashtags: [String]

        public init(platform: String, text: String, hashtags: [String]) {
            self.platform = platform
            self.text = text
            self.hashtags = hashtags
        }

        /// The text and the tags, ready to paste.
        public var pasteable: String {
            let tags = hashtags.map { "#" + $0 }.joined(separator: " ")
            return tags.isEmpty ? text : text + "\n\n" + tags
        }
    }

    /// The opening, judged: does it stop the scroll?
    public struct Hook: Hashable, Sendable, Codable {
        /// 1…10.
        public var score: Int
        /// The main problem, or empty when the opening is strong.
        public var issue: String
        /// A stronger first line to say instead.
        public var better: String

        public init(score: Int, issue: String, better: String) {
            self.score = score
            self.issue = issue
            self.better = better
        }
    }

    /// Two to five words for the cover image.
    public var cover: String
    public var title: String
    public var posts: [Post]
    public var hook: Hook
    public var bestTime: String

    public init(cover: String, title: String, posts: [Post], hook: Hook, bestTime: String) {
        self.cover = cover
        self.title = title
        self.posts = posts
        self.hook = hook
        self.bestTime = bestTime
    }
}

extension Project {
    /// What is said in the finished video, with the second each line starts, for the post kit.
    /// The captions as they play; the script when there are none yet.
    public var spokenTranscript: String {
        let cues = captionCues
        if !cues.isEmpty {
            return cues.map { "[\(Int($0.range.start.seconds.rounded()))] " + $0.text }.joined(separator: "\n")
        }
        return segments.map(\.script).filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
