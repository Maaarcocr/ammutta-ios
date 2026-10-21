import AmmuttaCore
import Foundation
import Testing
@testable import Ammutta

@MainActor
struct FormatTests {
    private let italian = Locale(identifier: "it_IT")
    private let english = Locale(identifier: "en_US")

    @Test func massUsesTheLocaleDecimalSeparator() {
        let it = Format.mass(.kilograms(62.5), unit: .kilograms, locale: italian)
        #expect(it.contains("62,5"))
        #expect(it.contains("kg"))
        let en = Format.mass(.kilograms(62.5), unit: .kilograms, locale: english)
        #expect(en.contains("62.5"))
    }

    @Test func massInPounds() {
        let text = Format.mass(.pounds(135), unit: .pounds, locale: english)
        #expect(text.contains("135"))
        #expect(text.contains("lb"))
    }

    @Test func wholeNumbersHaveNoDecimals() {
        #expect(!Format.mass(.kilograms(60), unit: .kilograms, locale: english).contains("."))
        #expect(Format.number(2.5, locale: italian) == "2,5")
    }

    @Test func clockFormat() {
        #expect(Format.clock(5) == "0:05")
        #expect(Format.clock(90) == "1:30")
        #expect(Format.clock(3723) == "1:02:03")
    }

    @Test func uniformSetsAreSummarizedOnce() {
        let sets = Array(repeating: SetValue.duration(seconds: 45), count: 3)
        let summary = Format.setsSummary(sets, unit: .kilograms)
        #expect(summary.contains("0:45"))
        #expect(!summary.contains("/"))
        let mixed = Format.setsSummary([.duration(seconds: 30), .duration(seconds: 45)], unit: .kilograms)
        #expect(mixed == "0:30 / 0:45")
    }
}
