//
//  TimelineViewModel.swift
//  GourmetShareMap
//

import Foundation
import Observation

/// タイムラインのデータ取得（`TimelineRepository`）。テストで差し替えられるようにプロトコルにしている。
protocol TimelineFeedFetching {
    func fetchFeed(since: Date) async throws -> TimelineFeed
}

extension TimelineRepository: TimelineFeedFetching {}

/// いいねの追加・取り消し（`LikeRepository`）。テストで差し替えられるようにプロトコルにしている。
protocol LikeToggling {
    func like(storeID: UUID) async throws
    func unlike(storeID: UUID) async throws
}

extension LikeRepository: LikeToggling {}

enum TimelineFilter: String, CaseIterable, Identifiable {
    case all = "すべて"
    case mine = "自分"
    case friends = "フレンド"

    var id: String { rawValue }
}

/// 日付ごとの見出し（今日・昨日・一昨日）と、その日の記録。
struct TimelineSection: Identifiable, Equatable {
    let day: Date
    let title: String
    let posts: [TimelinePost]

    var id: Date { day }
}

@Observable
final class TimelineViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// 今日を含めて何日分を表示するか（今日・昨日・一昨日）。
    static let dayRange = 3

    var filter: TimelineFilter = .all
    private(set) var posts: [TimelinePost] = []
    private(set) var friendCount = 0
    private(set) var loadState: LoadState = .idle

    private let repository: any TimelineFeedFetching
    private let likeRepository: any LikeToggling
    private let calendar: Calendar
    private let now: () -> Date

    /// 引数を省略すると Supabase に接続する本番の Repository を使う。
    init(
        repository: (any TimelineFeedFetching)? = nil,
        likeRepository: (any LikeToggling)? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now }
    ) {
        self.repository = repository ?? TimelineRepository()
        self.likeRepository = likeRepository ?? LikeRepository()
        self.calendar = calendar
        self.now = now
    }

    var filteredPosts: [TimelinePost] {
        switch filter {
        case .all: posts
        case .mine: posts.filter(\.isMine)
        case .friends: posts.filter { !$0.isMine }
        }
    }

    var sections: [TimelineSection] {
        let grouped = Dictionary(grouping: filteredPosts) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { day in
            TimelineSection(
                day: day,
                title: dayTitle(for: day),
                posts: grouped[day, default: []].sorted { $0.createdAt > $1.createdAt }
            )
        }
    }

    /// フレンドが 0 人で、表示する記録もないとき（「フレンドを探す」を促す空状態）。
    var showsNoFriendsState: Bool {
        loadState == .loaded && friendCount == 0 && filter != .mine && filteredPosts.isEmpty
    }

    func load() async {
        // 再読み込み中も前回の結果を表示したままにする。
        if posts.isEmpty { loadState = .loading }
        do {
            let feed = try await repository.fetchFeed(since: oldestDay)
            posts = feed.posts
            friendCount = feed.friendCount
            loadState = .loaded
        } catch is CancellationError {
            // タブ切り替えでタスクが取り消されたときは状態を変えない。
            if loadState == .loading { loadState = .idle }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// いいねの状態を即座に反転させてから送信する（楽観的更新）。失敗したら元に戻す。
    func toggleLike(for post: TimelinePost) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let wasLiked = posts[index].isLikedByMe
        posts[index] = posts[index].togglingLike()
        do {
            if wasLiked {
                try await likeRepository.unlike(storeID: post.id)
            } else {
                try await likeRepository.like(storeID: post.id)
            }
        } catch {
            if let revertIndex = posts.firstIndex(where: { $0.id == post.id }) {
                posts[revertIndex] = posts[revertIndex].togglingLike()
            }
        }
    }

    /// カード右上に出す投稿時刻。今日は「N時間前」、それ以前は「昨日 19:42」の形式。
    func timeText(for post: TimelinePost) -> String {
        let current = now()
        let day = calendar.startOfDay(for: post.createdAt)
        guard day == calendar.startOfDay(for: current) else {
            let time = post.createdAt.formatted(.verbatim(
                "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
                timeZone: calendar.timeZone,
                calendar: calendar
            ))
            return "\(dayTitle(for: day)) \(time)"
        }
        let minutes = max(0, Int(current.timeIntervalSince(post.createdAt) / 60))
        if minutes < 1 { return "たった今" }
        if minutes < 60 { return "\(minutes)分前" }
        return "\(minutes / 60)時間前"
    }

    /// 一昨日の 0 時。これ以降の記録を取得する。
    private var oldestDay: Date {
        let today = calendar.startOfDay(for: now())
        return calendar.date(byAdding: .day, value: -(Self.dayRange - 1), to: today) ?? today
    }

    private func dayTitle(for day: Date) -> String {
        let today = calendar.startOfDay(for: now())
        switch calendar.dateComponents([.day], from: day, to: today).day ?? 0 {
        case 0: return "今日"
        case 1: return "昨日"
        case 2: return "一昨日"
        default: return day.formatted(.dateTime.month().day())
        }
    }
}
