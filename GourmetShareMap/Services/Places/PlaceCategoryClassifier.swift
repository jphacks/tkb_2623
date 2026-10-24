import Foundation

// アプリとCLIテストで共有する日本語カテゴリの判定。
enum PlaceCategoryClassifier {
    // 順序はtypesが複数カテゴリに一致した場合の優先順位。「その他」は最後。
    static let categoryRules: [(name: String, types: Set<String>)] = [
        ("和食", "japanese_restaurant sushi_restaurant tonkatsu_restaurant yakitori_restaurant seafood_restaurant hot_pot_restaurant"),
        ("ラーメン・麺類", "ramen_restaurant noodle_shop chinese_noodle_restaurant"),
        ("焼肉・肉料理", "yakiniku_restaurant korean_barbecue_restaurant mongolian_barbecue_restaurant steak_house barbecue_restaurant chicken_restaurant chicken_wings_restaurant"),
        ("中華", "chinese_restaurant cantonese_restaurant dim_sum_restaurant dumpling_restaurant taiwanese_restaurant"),
        ("カレー", "japanese_curry_restaurant indian_restaurant north_indian_restaurant south_indian_restaurant pakistani_restaurant bangladeshi_restaurant sri_lankan_restaurant"),
        ("アジア・エスニック", "korean_restaurant thai_restaurant vietnamese_restaurant indonesian_restaurant malaysian_restaurant filipino_restaurant burmese_restaurant cambodian_restaurant tibetan_restaurant asian_restaurant asian_fusion_restaurant middle_eastern_restaurant turkish_restaurant lebanese_restaurant israeli_restaurant persian_restaurant afghani_restaurant moroccan_restaurant african_restaurant ethiopian_restaurant kebab_shop shawarma_restaurant falafel_restaurant gyro_restaurant"),
        ("洋食・西洋料理", "western_restaurant italian_restaurant pizza_restaurant french_restaurant bistro spanish_restaurant tapas_restaurant basque_restaurant portuguese_restaurant greek_restaurant mediterranean_restaurant german_restaurant bavarian_restaurant austrian_restaurant swiss_restaurant fondue_restaurant belgian_restaurant dutch_restaurant danish_restaurant scandinavian_restaurant british_restaurant irish_restaurant fish_and_chips_restaurant european_restaurant eastern_european_restaurant polish_restaurant czech_restaurant hungarian_restaurant croatian_restaurant romanian_restaurant russian_restaurant ukrainian_restaurant oyster_bar_restaurant american_restaurant californian_restaurant cajun_restaurant soul_food_restaurant southwestern_us_restaurant hawaiian_restaurant australian_restaurant mexican_restaurant tex_mex_restaurant taco_restaurant burrito_restaurant latin_american_restaurant south_american_restaurant brazilian_restaurant argentinian_restaurant peruvian_restaurant chilean_restaurant colombian_restaurant cuban_restaurant caribbean_restaurant"),
        ("ファストフード・食堂", "fast_food_restaurant hamburger_restaurant hot_dog_restaurant hot_dog_stand sandwich_shop deli salad_shop soup_restaurant snack_bar pizza_delivery meal_takeaway meal_delivery food_court cafeteria diner family_restaurant buffet_restaurant breakfast_restaurant brunch_restaurant"),
        ("カフェ・喫茶", "cafe coffee_shop coffee_stand coffee_roastery tea_house cat_cafe dog_cafe juice_shop acai_shop"),
        ("パン", "bakery bagel_shop"),
        ("スイーツ", "cake_shop pastry_shop donut_shop dessert_restaurant dessert_shop ice_cream_shop confectionery candy_store chocolate_shop chocolate_factory"),
        ("居酒屋・バー", "japanese_izakaya_restaurant bar bar_and_grill pub irish_pub gastropub brewpub brewery beer_garden wine_bar winery cocktail_bar lounge_bar sports_bar hookah_bar"),
        ("その他", "restaurant fusion_restaurant fine_dining_restaurant vegan_restaurant vegetarian_restaurant halal_restaurant"),
    ].map { (name: $0.0, types: Set($0.1.split(separator: " ").map(String.init))) }

    /// 13分類の名前を優先順位どおりに並べたもの。マップの絞り込みUIの選択肢として使う。
    static let categoryNames: [String] = categoryRules.map(\.name)

    static func category(primaryType: String?, types: [String]) -> String {
        // 主カテゴリが具体的なら優先する。汎用のrestaurant等は詳細typesで補完する。
        let specificRules = categoryRules.dropLast()
        if let primaryType,
           let rule = specificRules.first(where: { $0.types.contains(primaryType) }) {
            return rule.name
        }
        let typeSet = Set(types)
        return specificRules.first(where: { !$0.types.isDisjoint(with: typeSet) })?.name ?? "その他"
    }

}
