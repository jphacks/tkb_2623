import { historyCategoryFilter } from "./history_filter.ts";

function assert(value: unknown): asserts value {
  if (!value) throw new Error("Assertion failed");
}
Deno.test("requested genre maps to existing category and older labels", () => {
  const filter = historyCategoryFilter("あっさりしたラーメン");
  assert(filter.matches("ラーメン・麺類"));
  assert(filter.matches("ラーメン"));
  assert(!filter.matches("カフェ・喫茶"));
  assert(!filter.matches(null));
  assert(filter.query.startsWith('in.("ラーメン・麺類"'));
});
Deno.test("specific genres select their stored category, with longest aliases winning", () => {
  for (
    const [genre, category] of [
      ["カフェ", "カフェ・喫茶"],
      ["イタリアン", "洋食・西洋料理"],
      ["パンケーキ", "スイーツ"],
      ["焼肉", "焼肉・肉料理"],
      ["寿司", "和食"],
      ["韓国料理", "アジア・エスニック"],
      ["ＣＡＦＥ", "カフェ・喫茶"],
    ]
  ) assert(historyCategoryFilter(genre).matches(category));
});
Deno.test("unrecognized genres use literal partial matching and escape LIKE wildcards", () => {
  const filter = historyCategoryFilter("郷土料理");
  assert(filter.matches("北陸の郷土料理"));
  assert(!filter.matches("中華"));
  assert(filter.query === "ilike.%郷土料理%");
  assert(historyCategoryFilter("%_*").query === "ilike.%\\%\\_\\*%");
  assert(!historyCategoryFilter("barbecue").matches("居酒屋・バー"));
});
