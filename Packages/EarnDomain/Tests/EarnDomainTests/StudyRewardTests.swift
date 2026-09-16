import Foundation
import Testing
@testable import EarnDomain

@Suite("Study rewards")
struct StudyRewardTests {
    private let day = DayKey(year: 2027, month: 2, day: 10)
    private let issuedAt = Date(timeIntervalSince1970: 1_800_000_000)

    private func receipt(
        id: UUID = UUID(),
        seconds: Int = 600,
        date: Date? = nil,
        externalReference: String? = nil
    ) -> StudyRewardReceipt {
        StudyRewardReceipt(
            id: id,
            rewardSeconds: seconds,
            issuedAt: date ?? issuedAt,
            externalReference: externalReference
        )
    }

    @Test("A receipt credits the full reward and appends a study transaction")
    func appliesReceipt() {
        let reward = receipt(externalReference: "study-session-42")
        let outcome = StudyRewardEngine.apply(reward, to: .initial(day: day))

        #expect(outcome.result == .applied)
        #expect(outcome.awardedSeconds == 600)
        #expect(outcome.state.ledger.wallet.earnedSeconds == 600)
        #expect(outcome.state.ledger.walletTransactions == [
            WalletTransaction(kind: .earned, amountSeconds: 600, source: .study, date: issuedAt)
        ])
        #expect(outcome.state.appliedStudyReceiptIDs == [reward.id])
        #expect(outcome.state.ledger.rewardTransactions == [
            RewardTransaction(
                id: reward.id,
                method: .study,
                awardedSeconds: 600,
                issuedAt: issuedAt,
                externalReference: "study-session-42"
            )
        ])
    }

    @Test("A receipt remains a duplicate after encoding and restarting")
    func duplicateAfterRestart() throws {
        let reward = receipt()
        let applied = StudyRewardEngine.apply(reward, to: .initial(day: day)).state
        let restarted = try SharedState.decoded(from: applied.encoded())
        let duplicate = StudyRewardEngine.apply(reward, to: restarted)

        #expect(duplicate.result == .duplicate)
        #expect(duplicate.state == restarted)
        #expect(duplicate.state.ledger.wallet.earnedSeconds == 600)
        #expect(duplicate.state.ledger.walletTransactions.count == 1)
        #expect(duplicate.state.ledger.rewardTransactions.count == 1)
    }

    @Test("Receipt deduplication survives day rollover")
    func duplicateAfterRollover() {
        let reward = receipt()
        var state = StudyRewardEngine.apply(reward, to: .initial(day: day)).state
        state.ledger = CreditEngine.rollOverIfNeeded(state.ledger, to: day.adding(days: 1)!)
        let duplicate = StudyRewardEngine.apply(reward, to: state)

        #expect(duplicate.result == .duplicate)
        #expect(duplicate.state.ledger.wallet.earnedSeconds == 0)
        #expect(duplicate.state.appliedStudyReceiptIDs == [reward.id])
    }

    @Test("A reward is rejected entirely when the wallet lacks room")
    func insufficientRoom() {
        var state = SharedState.initial(day: day)
        state.ledger.wallet = ScreenTimeWallet(
            earnedSeconds: ScreenTimeWallet.maximumSavedSeconds - 300
        )
        let reward = receipt(seconds: 600)
        let outcome = StudyRewardEngine.apply(reward, to: state)

        #expect(outcome.result == .insufficientWalletCapacity)
        #expect(outcome.state == state)
        #expect(!outcome.state.appliedStudyReceiptIDs.contains(reward.id))
        #expect(outcome.state.ledger.walletTransactions.isEmpty)
        #expect(outcome.state.ledger.rewardTransactions.isEmpty)
    }

    @Test("Receipt deduplication retains old IDs")
    func durableDedupe() {
        let ids = (0...512).map { _ in UUID() }
        let state = SharedState(
            ledger: CreditEngine.startOfDay(day, rule: .default),
            appliedStudyReceiptIDs: ids
        )
        #expect(state.appliedStudyReceiptIDs.count == ids.count)
        #expect(state.appliedStudyReceiptIDs.first == ids.first)
        #expect(state.appliedStudyReceiptIDs.last == ids.last)

        let replay = StudyRewardEngine.apply(
            receipt(id: ids[0], date: issuedAt.addingTimeInterval(-1)),
            to: state
        )
        #expect(replay.result == .duplicate)
        #expect(replay.state.ledger.wallet.earnedSeconds == 0)
    }

    @Test("Distinct receipts with the same issue time both apply")
    func sameTimestampIsNotDuplicate() {
        let first = StudyRewardEngine.apply(receipt(), to: .initial(day: day)).state
        let second = StudyRewardEngine.apply(receipt(), to: first)

        #expect(second.result == .applied)
        #expect(second.state.ledger.wallet.earnedSeconds == 1_200)
    }

    @Test("Current-day reward audit persists and clears at rollover without changing history")
    func auditPersistenceAndRollover() throws {
        var state = StudyRewardEngine.apply(
            receipt(externalReference: "session-8"),
            to: .initial(day: day)
        ).state
        state = try SharedState.decoded(from: state.encoded())
        #expect(state.ledger.rewardTransactions.count == 1)
        #expect(state.ledger.rewardTransactions.first?.method == .study)
        #expect(state.ledger.rewardTransactions.first?.externalReference == "session-8")

        var history = ActivityHistory()
        history.record(state.ledger)
        state.ledger = CreditEngine.rollOverIfNeeded(state.ledger, to: day.adding(days: 1)!)
        #expect(state.ledger.rewardTransactions.isEmpty)
        #expect(history.days.first?.studyEarnedSeconds == 600)
    }

    @Test("Legacy and future reward audit fields decode tolerantly")
    func tolerantRewardTransaction() throws {
        let json = """
        {
          "method": "futureMethod",
          "awardedSeconds": 300
        }
        """
        let transaction = try JSONDecoder().decode(RewardTransaction.self, from: Data(json.utf8))
        #expect(transaction.method == .steps)
        #expect(transaction.awardedSeconds == 300)
        #expect(transaction.externalReference == nil)
    }

    @Test("Study earnings stay out of the step journey")
    func journeyIsStepOnly() {
        var state = CreditEngine.apply(activityAmount: 1_000, to: SharedState.initial(day: day).ledger).ledger
        var shared = SharedState(ledger: state)
        shared = StudyRewardEngine.apply(receipt(seconds: 900), to: shared).state
        state = shared.ledger
        let summary = DaySummary(ledger: state)
        let journey = ThirtyDayJourney(startDay: day, dailyGoal: 1_000).incorporating(summary)

        #expect(summary.earnedSeconds == 1_200)
        #expect(summary.stepEarnedSeconds == 300)
        #expect(summary.studyEarnedSeconds == 900)
        #expect(journey.earnedSeconds == 300)
    }

    @Test("Unknown wallet transaction sources decode as debug")
    func tolerantWalletSource() throws {
        let data = Data("\"futureSource\"".utf8)
        #expect(try JSONDecoder().decode(WalletTransaction.Source.self, from: data) == .debug)
    }

    @Test("The generic engine applies Pushups while the Study API remains source compatible")
    func genericRewardCompatibility() {
        let study: StudyRewardReceipt = receipt()
        let studied = StudyRewardEngine.apply(study, to: .initial(day: day)).state
        let pushups = ServerRewardReceipt(
            id: UUID(),
            method: .pushups,
            rewardSeconds: 300,
            issuedAt: issuedAt
        )
        let outcome = ServerRewardEngine.apply(pushups, to: studied)

        #expect(outcome.result == .applied)
        #expect(outcome.state.appliedRewardIDs == [study.id, pushups.id])
        #expect(outcome.state.ledger.walletTransactions.last?.source == .pushups)
        #expect(outcome.state.ledger.rewardTransactions.last?.method == .pushups)
    }

    @Test("Legacy Study receipt JSON defaults to the Study method")
    func legacyStudyReceiptDecoding() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "rewardSeconds": 600,
          "issuedAt": 100
        }
        """
        let decoded = try JSONDecoder().decode(StudyRewardReceipt.self, from: Data(json.utf8))
        #expect(decoded.method == .study)
    }

    @Test("Pushup earnings are separate from Study and never enter the step journey")
    func pushupHistoryClassification() {
        let pushed = ServerRewardEngine.apply(
            ServerRewardReceipt(id: UUID(), method: .pushups, rewardSeconds: 600, issuedAt: issuedAt),
            to: .initial(day: day)
        ).state
        let summary = DaySummary(ledger: pushed.ledger)
        let journey = ThirtyDayJourney(startDay: day, dailyGoal: 1_000).incorporating(summary)

        #expect(summary.earnedSeconds == 600)
        #expect(summary.stepEarnedSeconds == 0)
        #expect(summary.studyEarnedSeconds == 0)
        #expect(summary.pushupEarnedSeconds == 600)
        #expect(journey.earnedSeconds == 0)
    }
}
