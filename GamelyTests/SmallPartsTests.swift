import Testing
@testable import Gamely

struct UpdateVersionTests {
    @Test(arguments: [
        ("0.5.0", "0.3.0", true),
        ("0.10.0", "0.9.2", true),
        ("1.0", "0.9.9", true),
        ("0.5.0", "0.5.0", false),
        ("0.5", "0.5.0", false),
        ("0.4.9", "0.5.0", false),
    ])
    func isNewer(a: String, b: String, expected: Bool) {
        #expect(UpdateChecker.isNewer(a, than: b) == expected)
    }
}

struct HotCornerActionTests {
    @Test func describesActionWithModifiers() {
        #expect(HotCornerAction.describe(corner: 2, modifier: 1_048_576 | 131_072) == "⇧⌘ \(HotCornerAction.name(2))")
        #expect(HotCornerAction.describe(corner: 13, modifier: 0) == HotCornerAction.name(13))
    }

    @Test func noActionIsADash() {
        #expect(HotCornerAction.describe(corner: 0, modifier: 0) == "—")
        #expect(HotCornerAction.describe(corner: 1, modifier: 1_048_576) == "—")
    }
}

struct FrontmostGameTests {
    @Test(arguments: [
        ("public.app-category.games", true),
        ("public.app-category.action-games", true),
        ("public.app-category.puzzle-games", true),
        ("public.app-category.productivity", false),
        ("com.example.games", false),
    ])
    func gameCategories(category: String, expected: Bool) {
        #expect(FrontmostGame.isGameCategory(category) == expected)
    }
}
