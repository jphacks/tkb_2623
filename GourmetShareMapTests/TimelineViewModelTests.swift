//
//  TimelineViewModelTests.swift
//  GourmetShareMapTests
//

import Foundation
import Testing
@testable import GourmetShareMap

@MainActor
final class FakeTimelineFeedFetcher: TimelineFeedFetching {
    var feed = TimelineFeed(posts: [], friendCount: 0)
    var error: (any Error)?
    private(set) var requestedSince: [Date] = []

    func fetchFeed(since: Date) async throws -> TimelineFeed {
        requestedSince.append(since)
        if let error { throw error }
        return feed
    }
}

@MainActor
struct TimelineViewModelTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    /// 2026-10-24 15:00 (JST)
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 15))!
    }

    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func post(_ name: String, at createdAt: Date, isMine: Bool) -> TimelinePost {
        TimelinePost(
            id: UUID(), storeName: name, category: "カフェ・喫茶", userID: UUID(),
            userName: "あおい", isMine: isMine, createdAt: createdAt, coverImageURL: nil
        )
    }

    private func makeViewModel(_ fetcher: FakeTimelineFeedFetcher) -> TimelineViewModel {
        let now = now
        return TimelineViewModel(repository: fetcher, calendar: calendar, now: { now })
    }

    @Test func 一昨日の0時以降を取得する() async {
        let fetcher = FakeTimelineFeedFetcher()
        let viewModel = makeViewModel(fetcher)

        await viewModel.load()

        #expect(fetcher.requestedSince == [date(day: 22, hour: 0)])
        #expect(viewModel.loadState == .loaded)
    }

    @Test func 日付ごとに新しい順でまとめる() async {
        let fetcher = FakeTimelineFeedFetcher()
        fetcher.feed = TimelineFeed(posts: [
            post("昨日の店", at: date(day: 23, hour: 19, minute: 42), isMine: false),
            post("今日の朝", at: date(day: 24, hour: 9), isMine: true),
            post("今日の昼", at: date(day: 24, hour: 13), isMine: false),
            post("一昨日の店", at: date(day: 22, hour: 12), isMine: false),
        ], friendCount: 2)
        let viewModel = makeViewModel(fetcher)

        await viewModel.load()

        #expect(viewModel.sections.map(\.title) == ["今日", "昨日", "一昨日"])
        #expect(viewModel.sections[0].posts.map(\.storeName) == ["今日の昼", "今日の朝"])
        #expect(viewModel.friendCount == 2)
    }

    @Test func 自分とフレンドで絞り込める() async {
        let fetcher = FakeTimelineFeedFetcher()
        fetcher.feed = TimelineFeed(posts: [
            post("自分の店", at: date(day: 24, hour: 13), isMine: true),
            post("フレンドの店", at: date(day: 24, hour: 12), isMine: false),
        ], friendCount: 1)
        let viewModel = makeViewModel(fetcher)
        await viewModel.load()

        viewModel.filter = .mine
        #expect(viewModel.filteredPosts.map(\.storeName) == ["自分の店"])

        viewModel.filter = .friends
        #expect(viewModel.filteredPosts.map(\.storeName) == ["フレンドの店"])
    }

    @Test func 時刻の表示() {
        let viewModel = makeViewModel(FakeTimelineFeedFetcher())

        #expect(viewModel.timeText(for: post("a", at: date(day: 24, hour: 14, minute: 59),isMine: true)) == "1分前")
        #expect(viewModel.timeText(for: post("a", at: date(day: 24, hour: 13), isMine: true)) == "2時間前")
        #expect(viewModel.timeText(for: post("a", at: date(day: 23, hour: 19, minute: 42), isMine: true)) == "昨日 19:42")
        #expect(viewModel.timeText(for: post("a", at: date(day: 22, hour: 8, minute: 5), isMine: true)) == "一昨日 08:05")
    }

    @Test func フレンド0人で記録もなければ空状態() async {
        let fetcher = FakeTimelineFeedFetcher()
        let viewModel = makeViewModel(fetcher)
        await viewModel.load()
        #expect(viewModel.showsNoFriendsState)

        // 自分の記録があれば一覧を表示する。
        fetcher.feed = TimelineFeed(posts: [post("自分の店", at: date(day: 24, hour: 13), isMine: true)], friendCount: 0)
        await viewModel.load()
        #expect(!viewModel.showsNoFriendsState)
    }

    @Test func 取得失敗() async {
        let fetcher = FakeTimelineFeedFetcher()
        fetcher.error = URLError(.notConnectedToInternet)
        let viewModel = makeViewModel(fetcher)

        await viewModel.load()

        guard case .failed = viewModel.loadState else {
            Issue.record("失敗状態になっていない: \(viewModel.loadState)")
            return
        }
    }
}
