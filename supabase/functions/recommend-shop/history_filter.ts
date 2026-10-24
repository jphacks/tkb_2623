// Mirrors the 13 stored Japanese categories in Services/Places/ShopCategory.swift.
// Aliases also cover the older map categories and common free-form genre names.
const CATEGORIES: { name: string; aliases: string[] }[] = [
  {
    name: "和食",
    aliases: [
      "日本料理",
      "寿司",
      "すし",
      "鮨",
      "とんかつ",
      "焼き鳥",
      "焼鳥",
      "海鮮",
      "鍋",
      "sushi",
      "japanese",
    ],
  },
  {
    name: "ラーメン・麺類",
    aliases: [
      "ラーメン",
      "らーめん",
      "麺類",
      "うどん",
      "そば",
      "蕎麦",
      "つけ麺",
      "ramen",
      "noodle",
    ],
  },
  {
    name: "焼肉・肉料理",
    aliases: [
      "焼肉",
      "焼き肉",
      "肉料理",
      "ステーキ",
      "焼肉屋",
      "yakiniku",
      "steak",
    ],
  },
  {
    name: "中華",
    aliases: ["中華料理", "中国料理", "餃子", "飲茶", "台湾料理", "chinese"],
  },
  {
    name: "カレー",
    aliases: ["インド料理", "インドカレー", "curry", "indian"],
  },
  {
    name: "アジア・エスニック",
    aliases: [
      "アジア",
      "エスニック",
      "韓国料理",
      "タイ料理",
      "ベトナム料理",
      "thai",
      "vietnamese",
      "korean",
    ],
  },
  {
    name: "洋食・西洋料理",
    aliases: [
      "洋食",
      "西洋料理",
      "イタリアン",
      "イタリア料理",
      "フレンチ",
      "フランス料理",
      "パスタ",
      "ピザ",
      "italian",
      "french",
      "western",
    ],
  },
  {
    name: "ファストフード・食堂",
    aliases: [
      "ファストフード",
      "ファーストフード",
      "食堂",
      "ハンバーガー",
      "サンドイッチ",
      "定食",
      "fast food",
      "burger",
    ],
  },
  {
    name: "カフェ・喫茶",
    aliases: ["カフェ", "喫茶", "喫茶店", "コーヒー", "cafe", "café", "coffee"],
  },
  { name: "パン", aliases: ["パン屋", "ベーカリー", "bakery", "bread"] },
  {
    name: "スイーツ",
    aliases: [
      "ケーキ",
      "パンケーキ",
      "デザート",
      "アイス",
      "sweets",
      "dessert",
    ],
  },
  {
    name: "居酒屋・バー",
    aliases: [
      "居酒屋",
      "バー",
      "パブ",
      "ビール",
      "ワイン",
      "izakaya",
      "bar",
      "pub",
    ],
  },
  { name: "その他", aliases: ["other"] },
];

function normalized(value: string): string {
  return value.normalize("NFKC").trim().toLocaleLowerCase("ja");
}

export function historyCategoryFilter(genre: string): {
  query: string;
  matches: (category: unknown) => boolean;
} {
  const requested = normalized(genre);
  const containsAlias = (name: string) => {
    const token = normalized(name);
    return /^[a-z ]+$/.test(token)
      ? new RegExp(`(^|[^a-z])${token}($|[^a-z])`).test(requested)
      : requested.includes(token);
  };
  const exact = CATEGORIES.find((category) =>
    [category.name, ...category.aliases].some((name) =>
      normalized(name) === requested
    )
  );
  // The longest recognized genre wins (e.g. パンケーキ over パン).
  const candidates = CATEGORIES.flatMap((category) =>
    [category.name, ...category.aliases]
      .filter(containsAlias)
      .map((name) => ({ category, length: normalized(name).length }))
  );
  candidates.sort((a, b) => b.length - a.length);
  const selected = exact ?? candidates[0]?.category;
  if (selected) {
    const labels = [...new Set([selected.name, ...selected.aliases])];
    const known = new Set(labels.map(normalized));
    return {
      query: `in.(${labels.map((label) => JSON.stringify(label)).join(",")})`,
      matches: (category) =>
        typeof category === "string" && known.has(normalized(category)),
    };
  }
  // An unknown genre must not cause unrelated histories to be sent. Escape LIKE
  // wildcards so user input cannot widen the history query to all categories.
  const escaped = genre.normalize("NFKC").trim().replace(/[\\%_*]/g, "\\$&");
  return {
    query: `ilike.%${escaped}%`,
    matches: (category) =>
      typeof category === "string" && normalized(category).includes(requested),
  };
}
