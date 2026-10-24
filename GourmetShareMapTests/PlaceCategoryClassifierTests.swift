import Foundation
import Testing
@testable import GourmetShareMap

struct PlaceCategoryClassifierTests {
    @Test func categoryNamesListsAllThirteenCategoriesInOrderEndingWithOther() {
        let expected = [
            "和食", "ラーメン・麺類", "焼肉・肉料理", "中華", "カレー", "アジア・エスニック",
            "洋食・西洋料理", "ファストフード・食堂", "カフェ・喫茶", "パン", "スイーツ",
            "居酒屋・バー", "その他",
        ]
        #expect(PlaceCategoryClassifier.categoryNames == expected)
    }

    @Test func primaryTypeTakesPriorityOverConflictingTypes() {
        // primaryTypeが「ラーメン・麺類」に合致する場合、typesに「和食」系のtypeが混在していても優先される。
        let category = PlaceCategoryClassifier.category(
            primaryType: "ramen_restaurant",
            types: ["japanese_restaurant", "sushi_restaurant"]
        )
        #expect(category == "ラーメン・麺類")
    }

    @Test(arguments: [
        ("japanese_restaurant", "和食"),
        ("sushi_restaurant", "和食"),
        ("ramen_restaurant", "ラーメン・麺類"),
        ("yakiniku_restaurant", "焼肉・肉料理"),
        ("chinese_restaurant", "中華"),
        ("japanese_curry_restaurant", "カレー"),
        ("korean_restaurant", "アジア・エスニック"),
        ("italian_restaurant", "洋食・西洋料理"),
        ("fast_food_restaurant", "ファストフード・食堂"),
        ("cafe", "カフェ・喫茶"),
        ("bakery", "パン"),
        ("cake_shop", "スイーツ"),
        ("bar", "居酒屋・バー"),
    ])
    func primaryTypeMapsToExpectedCategory(primaryType: String, expected: String) {
        #expect(PlaceCategoryClassifier.category(primaryType: primaryType, types: []) == expected)
    }

    @Test func typesAreUsedWhenPrimaryTypeIsNil() {
        let category = PlaceCategoryClassifier.category(primaryType: nil, types: ["ramen_restaurant"])
        #expect(category == "ラーメン・麺類")
    }

    @Test func typesSupplementWhenPrimaryTypeMatchesNoSpecificCategory() {
        // primaryTypeが汎用の"restaurant"（13分類では「その他」専用）の場合、typesで具体カテゴリを補完する。
        let category = PlaceCategoryClassifier.category(
            primaryType: "restaurant",
            types: ["restaurant", "yakiniku_restaurant"]
        )
        #expect(category == "焼肉・肉料理")
    }

    @Test func firstMatchingRuleInDefinitionOrderWinsWhenTypesSpanMultipleCategories() {
        // 複数カテゴリのtypeを含む場合、categoryRulesの定義順で最初に一致したものが優先される。
        let category = PlaceCategoryClassifier.category(
            primaryType: nil,
            types: ["bar", "japanese_restaurant"]
        )
        #expect(category == "和食")
    }

    @Test func unmatchedPrimaryTypeAndTypesFallBackToOther() {
        #expect(PlaceCategoryClassifier.category(primaryType: "restaurant", types: ["restaurant"]) == "その他")
    }

    @Test func nilPrimaryTypeAndEmptyTypesFallBackToOther() {
        #expect(PlaceCategoryClassifier.category(primaryType: nil, types: []) == "その他")
    }

    @Test func unknownPrimaryTypeAndTypesFallBackToOther() {
        #expect(PlaceCategoryClassifier.category(primaryType: "unknown_type", types: ["also_unknown"]) == "その他")
    }
}
