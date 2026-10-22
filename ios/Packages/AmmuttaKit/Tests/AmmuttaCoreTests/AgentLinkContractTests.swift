import Foundation
import Testing
@testable import AmmuttaCore

/// The agent connector (server/src/plans.ts) writes plans as links; the app must parse them.
/// Keep this link identical to the one in server/test/plans.test.ts.
struct AgentLinkContractTests {
    @Test func parsesTheLinkTheServerBuilds() throws {
        let link = "ammutta://plan?v=1&name=Push%20Day&unit=lb&e=barbell-bench-press%3A3x8%40135%3A150&e=Band%20Pull-Apart%3A3x15"
        let draft = try PlanLink.parse(link)
        #expect(draft.name == "Push Day")
        #expect(draft.exercises.count == 2)
        #expect(draft.exercises[0].reference == .builtIn(key: "barbell-bench-press"))
        #expect(draft.exercises[0].sets == Array(repeating: .reps(count: 8, weight: .pounds(135)), count: 3))
        #expect(draft.exercises[0].restSeconds == 150)
        #expect(draft.exercises[1].reference == .named("Band Pull-Apart"))
        #expect(draft.exercises[1].restSeconds == nil)
    }
}
