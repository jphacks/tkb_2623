// 料理写真から抽出する JSON のテンプレート（語彙 v1）。
// 出典: 「料理写真の特徴抽出スキーマ（高解像度版）」2026-10-24。
// 語彙を変えるときはこのファイルを直接書き換えず v2.ts を作り、SCHEMA_VERSION を上げる。
//
// 出力される JSON の形:
//   {
//     "category": store.category の値,
//     "format": formats のどれか,
//     "lineage": lineages のどれか,
//     "parts":  { 部品: { 属性: 値 } },   ← カテゴリの部品表（partTables）。「その他」は null
//     "common": { 部品: { 属性: 値 } },   ← 全カテゴリ共通（COMMON_PARTS）
//     "caption": 料理の短い説明
//   }
// 値の書き方は EXTRACTION_RULES に従う（Gemini への指示にも使う）。

export const SCHEMA_VERSION = "v1";

/** 値の書き方のルール。 */
export const EXTRACTION_RULES: readonly string[] = [
  "選択肢・段階評価がある属性は、定義された値の中から選ぶ。",
  "写真に写っていない、または写っていても判断できない部品・属性は null にする。推測で埋めない。",
  "「なし」は、写っていて無いと確認できる場合だけ使う（例: 丼の表面全体が見えていて卵が無い）。",
  "自由に列挙する属性（tags）は、写真から種類が分かるものだけを書く。分からないものは書かない。",
  "人物・顔・名札、レシートや画面の文字は記述しない。",
];

/** 属性の値の種類。 */
export type Attribute =
  /** 選択肢から1つ選ぶ（multiple なら複数）。 */
  | { kind: "choice"; label: string; options: readonly string[]; multiple?: boolean }
  /** 段階評価。criteria は両端（必要なら中間）の目視の基準。 */
  | { kind: "scale"; label: string; min: number; max: number; criteria: string }
  /** 個数などの整数。 */
  | { kind: "count"; label: string }
  /** 0〜1 の割合。 */
  | { kind: "ratio"; label: string }
  /** 種類を自由に列挙する（examples は例）。 */
  | { kind: "tags"; label: string; examples: readonly string[] }
  | { kind: "boolean"; label: string };

export type Part = { label: string; attributes: Record<string, Attribute> };

/** 部品表。formats に含まれる形式の料理に使う（和食は形式ごとに表が分かれる）。 */
export type PartTable = { formats: readonly string[]; parts: Record<string, Part> };

export type CategoryVocab = {
  formats: readonly string[];
  lineages: readonly string[];
  /** 空のカテゴリ（その他）は parts を出力しない。 */
  partTables: readonly PartTable[];
};

const choice = (label: string, options: readonly string[]): Attribute => ({ kind: "choice", label, options });
const multi = (label: string, options: readonly string[]): Attribute => ({
  kind: "choice",
  label,
  options,
  multiple: true,
});
const scale = (label: string, min: number, max: number, criteria: string): Attribute => ({
  kind: "scale",
  label,
  min,
  max,
  criteria,
});
const count = (label: string): Attribute => ({ kind: "count", label });
const ratio = (label: string): Attribute => ({ kind: "ratio", label });
const tags = (label: string, examples: readonly string[]): Attribute => ({ kind: "tags", label, examples });
const flag = (label: string): Attribute => ({ kind: "boolean", label });
const part = (label: string, attributes: Record<string, Attribute>): Part => ({ label, attributes });

/** 全カテゴリ共通の属性。撮影時間帯は写真の EXIF から取るため Gemini には聞かない。 */
export const COMMON_PARTS: Record<string, Part> = {
  overall: part("全体", {
    volume: scale("ボリューム", 1, 5, "1 控えめ ／ 3 普通 ／ 5 器からはみ出す"),
    component_kinds: count("構成要素の種類数（トッピング・具・付け合わせの種類）"),
    plating: choice("盛り付けスタイル", ["素朴", "豪快（山盛り）", "整然（区画盛り）", "映え（色・高さ）", "上品（余白多め）"]),
    color_impression: choice("色の印象", ["茶系中心", "赤系", "白系", "緑多め", "カラフル"]),
    temperature: choice("温度", ["熱い（湯気）", "常温", "冷たい（結露・氷）"]),
  }),
  vessel: part("器", {
    material: choice("素材", ["磁器", "陶器", "漆・木", "ガラス", "金属", "紙・プラスチック"]),
    style: choice("色柄・テイスト", ["和（染付・土物）", "洋（白無地・リム皿）", "中華（雷紋・赤）", "モダン", "大衆"]),
    shape: choice("形", ["丼", "深皿", "平皿", "ボウル", "鉄板・鍋", "カップ・グラス"]),
  }),
  surroundings: part("周辺", {
    drink: choice("飲み物", ["水のみ", "ソフトドリンク", "茶", "コーヒー", "酒"]),
    side: tags("サイド（主役以外の料理）", ["餃子", "ライス", "小鉢"]),
    party_size: choice("人数の手がかり（皿・グラス・取り皿の数）", ["1人分", "2人以上"]),
    condiments: tags("卓上調味料", ["にんにく", "辣油", "胡椒", "ソース"]),
    lighting: choice("店内の照明", ["明るい", "暗め"]),
    seat: choice("席", ["カウンター", "テーブル", "座敷", "テラス"]),
    takeout: flag("テイクアウト（包装・紙袋）"),
  }),
};

// ---------- 1. 和食（形式ごとに表が分かれる） ----------

const WASHOKU_FORMATS = {
  sushi: "寿司（握り・巻き・ちらし）",
  sashimi: "刺身",
  donburi: "海鮮丼・丼",
  teishoku: "定食",
  fried: "揚げ物（とんかつ・天ぷら）",
  yakitori: "焼き鳥・串",
  nabe: "鍋",
  unagi: "うなぎ",
  other: "会席・その他",
} as const;

const WASHOKU: CategoryVocab = {
  formats: Object.values(WASHOKU_FORMATS),
  lineages: [
    "江戸前寿司", "回転寿司", "海鮮丼", "厚切りとんかつ", "天ぷら専門", "焼き鳥（タレ派）", "焼き鳥（塩派）",
    "もつ鍋", "しゃぶしゃぶ・すき焼き", "定食屋", "割烹・会席", "その他",
  ],
  partTables: [
    {
      // 寿司・刺身・海鮮。丼は「盛り」の基準があるためこの表を使う。
      formats: [WASHOKU_FORMATS.sushi, WASHOKU_FORMATS.sashimi, WASHOKU_FORMATS.donburi],
      parts: {
        neta: part("ネタ", {
          composition: multi("種類の構成", [
            "赤身", "中トロ・大トロ", "白身", "光り物", "貝", "甲殻類", "いくら・うに", "穴子・煮物",
          ]),
          preparation: multi("仕事", ["生", "炙り", "漬け", "〆（昆布・酢）", "煮"]),
          thickness: choice("切り身の厚み", ["薄", "中", "厚"]),
          fat_look: scale("脂の見た目", 0, 4, "0 透明感のある赤身 ／ 4 白いサシが全面"),
        }),
        shari: part("シャリ", {
          color: choice("色", ["白（米酢）", "薄茶（赤酢）"]),
          size: choice("大きさ", ["小ぶり", "普通", "大きめ"]),
        }),
        serving: part("盛り", {
          piece_count: count("貫数・切れ数"),
          coverage: scale("丼の覆い方（丼のみ）", 1, 5, "1 ご飯が見える ／ 5 ネタで完全に覆う"),
        }),
        condiments: part("薬味", {
          types: multi("種類", ["わさび", "ガリ", "大葉", "柑橘", "ねぎ"]),
        }),
      },
    },
    {
      formats: [WASHOKU_FORMATS.fried],
      parts: {
        batter: part("衣", {
          grain: choice("粒の粗さ（パン粉の立ち方）", ["細", "中", "粗"]),
          color: scale("色", 1, 5, "1 白っぽい ／ 5 濃いきつね色"),
          thickness: choice("厚み", ["薄衣", "普通", "厚衣"]),
        }),
        filling: part("中身", {
          types: multi("種類", ["ロース", "ヒレ", "海老", "魚", "野菜", "鶏"]),
          thickness: choice("厚み（断面の高さ）", ["薄", "中", "厚"]),
          cross_section_color: choice("断面の色", ["ピンクが残る", "全体に白い"]),
        }),
        seasoning: part("味付け", {
          style: choice("かけ方", ["ソースがけ", "ソース別添", "塩", "天つゆ", "卵とじ"]),
        }),
        garnish: part("付け合わせ", {
          cabbage_amount: scale("キャベツ千切りの量", 0, 4, "0 なし ／ 4 山盛り"),
          items: multi("種類", ["ご飯", "味噌汁", "漬物"]),
        }),
      },
    },
    {
      formats: [WASHOKU_FORMATS.yakitori],
      parts: {
        skewers: part("串", {
          cuts: multi("部位の構成", [
            "もも", "ねぎま", "皮", "つくね", "レバー", "ハツ", "砂肝", "ぼんじり", "手羽", "野菜",
          ]),
          tare_ratio: ratio("タレの本数の比率（残りは塩）"),
          char: scale("焼き色", 1, 5, "1 淡い ／ 5 焦げが強い"),
          piece_size: choice("一切れの大きさ", ["小", "中", "大"]),
        }),
        condiments: part("添え", {
          types: multi("種類", ["山椒", "七味", "柚子胡椒", "卵黄（つくね）"]),
        }),
      },
    },
    {
      formats: [WASHOKU_FORMATS.nabe],
      parts: {
        soup: part("スープ", {
          base: choice("系統", ["昆布出汁（透明）", "白湯", "醤油割下", "味噌", "辛味（赤）"]),
          turbidity: scale("濁り", 1, 5, "1 底まで透ける ／ 5 不透明"),
        }),
        main: part("主素材", {
          types: multi("種類", ["豚", "牛", "鶏", "もつ", "魚介"]),
          amount: scale("量", 0, 4, "0 ほぼなし ／ 4 鍋を覆う"),
        }),
        vegetables: part("野菜", {
          amount: scale("量", 0, 4, "0 ほぼなし ／ 4 鍋を覆う"),
        }),
        state: part("状態", {
          stage: choice("調理段階", ["煮る前", "煮込み中", "〆（雑炊・麺）"]),
        }),
      },
    },
    {
      formats: [WASHOKU_FORMATS.teishoku, WASHOKU_FORMATS.unagi, WASHOKU_FORMATS.other],
      parts: {
        main_dish: part("主菜", {
          method: choice("調理法", ["焼き", "煮", "揚げ", "生", "蒸し"]),
          ingredient: choice("主素材", ["魚", "豚", "鶏", "牛", "卵", "豆腐"]),
        }),
        side_dishes: part("副菜", {
          count: count("小鉢の数"),
        }),
        rice: part("ご飯", {
          type: choice("種類", ["白米", "雑穀", "炊き込み"]),
          amount: choice("量", ["小", "並", "大"]),
        }),
        soup: part("汁物", {
          type: choice("種類", ["味噌汁", "すまし汁", "豚汁", "なし"]),
        }),
      },
    },
  ],
};

// ---------- 2. ラーメン・麺類 ----------

const RAMEN_FORMATS = ["汁あり", "つけ麺", "汁なし・まぜそば", "うどん", "そば", "その他の麺"];

const RAMEN: CategoryVocab = {
  formats: RAMEN_FORMATS,
  lineages: [
    "淡麗醤油", "背脂醤油", "家系", "二郎系", "博多豚骨", "札幌味噌", "鶏白湯", "煮干し", "担々麺",
    "濃厚魚介つけ麺", "油そば・まぜそば", "讃岐うどん", "手打ちそば", "その他",
  ],
  partTables: [
    {
      formats: RAMEN_FORMATS,
      parts: {
        soup: part("スープ", {
          base: choice("系統", ["醤油", "塩", "味噌", "豚骨", "鶏白湯", "魚介・煮干し", "担々・辛味"]),
          turbidity: scale("濁り", 1, 5, "1 底まで透ける ／ 3 半透明 ／ 5 不透明"),
          color_depth: scale("色の濃さ", 1, 5, "1 淡い黄金 ／ 3 琥珀 ／ 5 黒に近い"),
          viscosity: choice("粘度", ["さらさら", "とろみ", "ポタージュ状"]),
        }),
        tare: part("タレ（汁なし・まぜそば）", {
          color: choice("色", ["白っぽい（乳化）", "醤油色", "赤（辛味）", "黒（マー油など）"]),
          amount: scale("量", 0, 4, "0 ほぼ見えない ／ 4 器の底にたっぷり溜まる"),
          oiliness: scale("油っぽさ", 0, 4, "0 油が見えない ／ 4 油が厚く光る"),
        }),
        oil: part("油", {
          types: multi("種類", ["背脂粒", "鶏油（黄色い油）", "ラー油", "マー油（黒い油）", "ネギ油", "なし"]),
          amount: scale("量", 0, 4, "0 見えない ／ 4 表面を厚く覆う"),
          fat_grain: choice("背脂の粒", ["細かい", "粗い"]),
        }),
        sprinkles: part("振りもの", {
          types: multi("種類", ["黒胡椒", "白ごま", "魚粉", "刻み玉ねぎ", "唐辛子", "柚子皮"]),
        }),
        noodle: part("麺", {
          thickness: choice("太さ", ["極細", "細", "中細", "中太", "太", "極太"]),
          shape: choice("形", ["ストレート", "ウェーブ", "強縮れ", "平打ち", "手もみ"]),
          color: choice("色", ["白っぽい", "黄色（かん水強め）", "茶色・粒あり（全粒粉）"]),
          amount: choice("量（器に対する高さ）", ["並", "大盛り", "特盛り"]),
        }),
        chashu: part("チャーシュー", {
          type: choice("種類", ["煮豚", "低温調理（ピンク）", "炙り", "バラ巻き", "鶏", "鴨"]),
          thickness: choice("厚さ", ["薄", "中", "厚"]),
          count: count("枚数"),
          area_ratio: ratio("丼の表面に占める割合（0.1 刻み）"),
        }),
        egg: part("卵", {
          yolk: choice("黄身の状態", ["なし", "固ゆで", "半熟", "とろとろ", "生黄身"]),
          seasoning_color: choice("味付けの色", ["白", "淡い茶", "濃い茶"]),
        }),
        menma: part("メンマ", {
          shape: choice("形", ["細切り", "太切り", "穂先", "板状"]),
        }),
        negi: part("ネギ", {
          type: choice("種類", ["青ネギ小口", "白髪ネギ", "九条ネギ", "玉ねぎ角切り", "なし"]),
        }),
        other_toppings: part("その他の具", {
          types: multi("種類", [
            "海苔", "岩のり・ばら海苔", "もやし", "キャベツ", "ほうれん草", "なると・かまぼこ", "肉味噌", "にら", "にんにく",
          ]),
          amount: scale("量（器の表面に占める広さ）", 0, 4, "0 ほぼなし ／ 2 器の4分の1程度 ／ 4 器の半分以上を覆う"),
          nori_count: count("板海苔の枚数"),
        }),
        dipping_sauce: part("つけ汁（つけ麺）", {
          thickness: scale("濃度", 1, 5, "1 さらさら ／ 5 どろどろ"),
          noodle_temperature: choice("麺の温度", ["冷", "あつもり"]),
        }),
        tsuyu: part("つゆ（うどん・そば）", {
          color: choice("色", ["淡口（関西）", "濃口（関東）"]),
        }),
        soba: part("麺（そば）", {
          color: choice("色", ["更科（白）", "田舎（黒い粒）"]),
        }),
      },
    },
  ],
};

// ---------- 3. 焼肉・肉料理 ----------

const YAKINIKU_FORMATS = [
  "焼肉（焼く前の皿）", "焼肉（網の上）", "ステーキ", "BBQ・スモーク", "フライドチキン・手羽", "ジンギスカン",
];

const YAKINIKU: CategoryVocab = {
  formats: YAKINIKU_FORMATS,
  lineages: [
    "大衆焼肉", "高級和牛焼肉", "ホルモン", "韓国焼肉（サムギョプサル）", "ジンギスカン", "熟成肉ステーキ",
    "ファミリー向けステーキ", "アメリカンBBQ", "フライドチキン", "手羽先", "その他",
  ],
  partTables: [
    {
      formats: YAKINIKU_FORMATS,
      parts: {
        meat: part("肉", {
          cuts: multi("部位", [
            "タン", "カルビ", "ロース", "ハラミ", "ホルモン", "ヒレ", "サーロイン", "リブ", "豚バラ", "鶏もも", "手羽", "羊",
          ]),
          marbling: scale("サシ", 0, 4, "0 赤身のみ ／ 4 霜降りが全面"),
          thickness: choice("厚み", ["薄切り", "中", "厚切り", "ブロック"]),
          assortment: choice("盛り合わせの構成", ["赤身中心", "霜降り中心", "ホルモン中心", "混合"]),
        }),
        grilling: part("焼き", {
          doneness: choice("焼き加減（断面の色）", ["焼く前", "レア", "ミディアム", "ウェルダン"]),
          char: scale("焦げ目", 0, 4, "0 なし ／ 4 強い焦げ・炭の跡"),
        }),
        seasoning: part("味付け", {
          type: choice("種類", [
            "タレ漬け", "塩・レモン", "味噌", "ヤンニョム（赤い甘辛）", "デミ・ガーリックソース", "スパイスラブ",
          ]),
        }),
        coating: part("衣（チキン）", {
          type: choice("種類", ["薄粉", "ザクザクの厚衣"]),
          color: scale("色", 1, 5, "1 淡い ／ 5 濃い"),
        }),
        garnish: part("付け合わせ", {
          types: multi("種類", ["サンチュ", "キムチ・ナムル", "ポテト", "コーン", "ライス", "コールスロー"]),
        }),
        equipment: part("調理器具", {
          type: choice("種類", ["網", "鉄板", "ロースター", "七輪", "鋳鉄皿", "ジンギスカン鍋"]),
        }),
        amount: part("量", {
          plate_count: count("皿の数"),
          meat_ratio: ratio("皿に占める肉の割合（ステーキ）"),
        }),
      },
    },
  ],
};

// ---------- 4. 中華 ----------

const CHUKA_FORMATS = [
  "炒め物", "揚げ物", "点心", "餃子", "麺", "飯もの（炒飯・丼）", "スープ・煮込み", "ロースト（北京ダック・叉焼）",
];

const CHUKA: CategoryVocab = {
  formats: CHUKA_FORMATS,
  lineages: ["町中華", "四川（麻辣）", "広東・飲茶", "上海", "台湾（魯肉飯・小籠包）", "高級中華", "餃子専門", "その他"],
  partTables: [
    {
      formats: CHUKA_FORMATS,
      parts: {
        sauce: part("ソース", {
          color: choice("色・系統", [
            "透明（塩）", "醤油色", "甘酢（照りのある赤橙）", "豆板醤（赤）", "麻辣（赤い油＋花椒）", "白（クリーム煮）",
            "黒（黒酢・豆豉）",
          ]),
          thickness: scale("とろみ", 0, 3, "0 さらさら ／ 3 あんが厚く絡む"),
        }),
        oil: part("油", {
          gloss: scale("照り・量", 0, 4, "0 なし ／ 4 皿に油がたまる"),
        }),
        main: part("主素材", {
          types: multi("種類", ["豚", "鶏", "牛", "海老", "イカ", "豆腐", "卵", "野菜"]),
          cut: choice("切り方", ["細切り", "角切り", "薄切り", "ぶつ切り"]),
        }),
        spices: part("香辛料（見える量）", {
          chili: scale("唐辛子", 0, 4, "0 なし ／ 4 多い"),
          sichuan_pepper: scale("花椒", 0, 4, "0 なし ／ 4 多い"),
          star_anise: scale("八角", 0, 4, "0 なし ／ 4 多い"),
          cilantro: scale("パクチー", 0, 4, "0 なし ／ 4 多い"),
          negi: scale("ねぎ", 0, 4, "0 なし ／ 4 多い"),
        }),
        gyoza: part("餃子", {
          method: choice("調理法", ["焼き", "水", "蒸し", "揚げ"]),
          wing: flag("羽根あり"),
          browning: scale("焼き色", 1, 5, "1 淡い ／ 5 濃い"),
          size: choice("形", ["小ぶり", "普通", "大ぶり"]),
          skin: choice("皮", ["薄", "厚"]),
        }),
        dim_sum: part("点心", {
          types: multi("種類", ["小籠包", "焼売", "蝦餃", "春巻", "大根餅", "肉まん"]),
          skin: choice("皮", ["透ける薄皮", "厚めの白い皮"]),
        }),
        fried_rice: part("炒飯", {
          separation: scale("粒立ち", 1, 5, "1 しっとり ／ 5 パラパラ"),
          color: choice("色", ["白", "卵の黄色", "醤油色"]),
        }),
        sharing: part("量", {
          plate_count: count("皿の数"),
          small_plate_count: count("取り皿の数"),
        }),
      },
    },
  ],
};

// ---------- 5. カレー ----------

const CURRY_FORMATS = [
  "カレーライス", "トッピング系（カツカレーなど）", "ナンセット", "ミールス・ターリー", "ビリヤニ", "スープカレー", "キーマ",
];

const CURRY: CategoryVocab = {
  formats: CURRY_FORMATS,
  lineages: [
    "日本の家庭風", "欧風", "金沢カレー", "大阪スパイスカレー", "北インド（ナン系）", "南インド・ミールス",
    "スリランカのライス＆カリー", "ネパールのダルバート", "スープカレー", "ビリヤニ", "その他",
  ],
  partTables: [
    {
      formats: CURRY_FORMATS,
      parts: {
        roux: part("ルウ・グレイビー", {
          color: choice("色", ["黄", "茶", "濃茶・黒", "赤橙", "緑（サグ）", "白（コルマ）"]),
          color_depth: scale("色の濃さ", 1, 5, "1 淡い ／ 5 黒に近い"),
          thickness: choice("とろみ", ["さらさら（スープ状）", "中", "もったり"]),
          oil: scale("油の浮き", 0, 4, "0 なし ／ 4 表面に赤い油の層"),
          type: choice("種類", ["欧風", "和風", "バターチキン", "キーマ", "ダル（豆）", "サグ", "魚", "ビンダルー"]),
        }),
        staple: part("主食", {
          type: choice("種類", [
            "ご飯（白）", "ご飯（ターメリック）", "ご飯（長粒）", "ナン（プレーン）", "ナン（チーズ）", "ナン（ガーリック）",
            "チャパティ", "パラタ", "ビリヤニ",
          ]),
          naan_size: choice("ナンの大きさ", ["皿に収まる", "皿からはみ出す"]),
        }),
        filling: part("具", {
          ingredients: multi("主素材", ["鶏", "牛", "豚", "羊", "魚介", "豆", "野菜"]),
          size: choice("大きさ", ["溶け込み", "小さめ", "ゴロゴロ", "骨付き"]),
        }),
        topping: part("トッピング", {
          types: multi("種類", ["カツ", "チーズ", "卵", "揚げ野菜", "ハンバーグ"]),
        }),
        side_dishes: part("副菜", {
          types: multi("種類", ["福神漬け", "らっきょう", "アチャール", "ライタ", "パパド", "サラダ"]),
        }),
        composition: part("構成", {
          curry_kinds: choice("カレーの種類数", ["1種", "あいがけ2種", "3種以上"]),
          small_plate_count: count("小皿の数（ミールス）"),
        }),
        spice: part("スパイス（見た目）", {
          whole_spices: flag("ホールスパイスあり"),
          green_chili: flag("生の青唐辛子あり"),
          cilantro: flag("パクチーあり"),
        }),
      },
    },
  ],
};

// ---------- 6. アジア・エスニック ----------

const ASIAN_FORMATS = [
  "麺", "ご飯もの", "スープ・鍋", "巻く・挟む（ケバブ・シャワルマ・バインミー・生春巻き）",
  "プレート（フムス・ファラフェル）", "揚げ物・グリル",
];

const ASIAN: CategoryVocab = {
  formats: ASIAN_FORMATS,
  lineages: [
    "韓国（チゲ・ビビンバ・韓国チキン）", "タイ（ガパオ・グリーンカレー・トムヤム）", "ベトナム（フォー・バインミー・生春巻き）",
    "インドネシア・マレーシア（ナシゴレン・ラクサ）", "中東（ケバブ・シャワルマ・ファラフェル・フムス）", "トルコ", "ペルシャ",
    "エチオピア", "その他",
  ],
  partTables: [
    {
      formats: ASIAN_FORMATS,
      parts: {
        region: part("地域", {
          area: choice("地域", [
            "韓国", "タイ", "ベトナム", "インドネシア・マレーシア・フィリピン", "その他アジア", "中東・トルコ・ペルシャ",
            "アフリカ",
          ]),
        }),
        base: part("味の土台", {
          types: multi("種類", [
            "ココナッツ（白濁）", "魚醤・ナンプラー", "コチュジャン・唐辛子", "ライム・タマリンド（酸味）", "ヨーグルト",
            "タヒニ・ごま", "ピーナッツ", "スパイス",
          ]),
          redness: scale("赤さ", 0, 4, "0 赤みなし ／ 4 全体が赤い"),
        }),
        herbs: part("ハーブ", {
          types: multi("種類", ["パクチー", "ミント", "バジル", "ディル", "レモングラス", "パセリ"]),
          amount: scale("量", 0, 4, "0 なし ／ 4 たっぷり"),
        }),
        fresh_chili: part("生唐辛子", {
          amount: scale("量", 0, 4, "0 なし ／ 4 たっぷり"),
        }),
        main: part("主素材", {
          types: multi("種類", ["鶏", "豚", "牛", "羊", "魚介", "豆（ひよこ豆）", "豆腐", "卵"]),
          method: choice("調理法", ["グリル・串", "煮込み", "揚げ", "炒め", "生"]),
        }),
        staple: part("主食", {
          type: choice("種類", [
            "ジャスミン米", "もち米", "米麺（細）", "米麺（平）", "小麦麺", "ピタ・薄焼きパン", "インジェラ",
          ]),
        }),
        fresh_vegetables: part("生野菜", {
          amount: scale("量", 0, 4, "0 なし ／ 4 皿の半分以上"),
        }),
        side_dishes: part("副菜", {
          count: count("小皿の数（韓国のパンチャンなど）"),
        }),
        garnish: part("添え", {
          types: multi("種類", ["ライム", "ピクルス", "ナッツ", "フライドオニオン", "ヨーグルトソース", "チリソース"]),
        }),
        serving_vessel: part("器", {
          feature: choice("特徴", ["石鍋", "ステンレス食器", "バナナの葉", "金属トレー"]),
        }),
      },
    },
  ],
};

// ---------- 7. 洋食・西洋料理 ----------

const WESTERN_FORMATS = [
  "パスタ", "ピザ", "肉料理", "魚料理", "前菜・サラダ", "米料理（リゾット・パエリア）", "煮込み・スープ", "タコス・ブリトー",
  "牡蠣・海鮮盛り",
];

const WESTERN: CategoryVocab = {
  formats: WESTERN_FORMATS,
  lineages: [
    "トラットリア", "ナポリピザ", "アメリカンピザ", "生パスタ専門", "フレンチ・ビストロ", "スペインバル（タパス・パエリア）",
    "ドイツ料理", "英国（フィッシュ＆チップス）", "アメリカン", "メキシカン・タコス", "シュラスコ", "日本の洋食",
    "オイスターバー", "その他",
  ],
  partTables: [
    {
      formats: WESTERN_FORMATS,
      parts: {
        region: part("地域", {
          area: choice("地域", [
            "イタリア", "フランス", "スペイン・地中海", "ドイツ・中東欧・北欧", "英国・アイルランド", "アメリカ・オセアニア",
            "メキシコ・中南米", "日本の洋食",
          ]),
        }),
        sauce: part("ソース", {
          type: choice("系統", [
            "トマト", "クリーム", "オイル・ガーリック", "バター", "デミグラス", "チーズ", "ジェノベーゼ", "ワイン煮込み", "サルサ",
          ]),
          amount: choice("量", ["絡む程度", "皿に広がる", "たっぷり"]),
          color_depth: scale("色の濃さ", 1, 5, "1 淡い ／ 5 濃い"),
        }),
        pasta: part("パスタ", {
          type: choice("麺の種類", ["ロング細", "ロング太", "平打ち", "ショート", "生パスタ"]),
        }),
        pizza: part("ピザ", {
          dough: choice("生地", ["ナポリ（縁が膨らみ焦げ斑点）", "ローマ（薄くカリカリ）", "アメリカン（厚い）"]),
          char_spots: scale("焦げ斑点", 0, 4, "0 なし ／ 4 多い"),
          cheese_amount: scale("チーズ量", 0, 4, "0 なし ／ 4 たっぷり"),
          topping_kinds: count("トッピングの種類数"),
        }),
        protein: part("肉・魚", {
          type: choice("種類", ["牛", "豚", "鶏", "羊", "鴨", "白身魚", "青魚", "甲殻類"]),
          method: choice("調理法", ["グリル", "ロースト", "ソテー", "煮込み", "フライ", "カルパッチョ（生）"]),
          doneness: choice("焼き加減（断面の色）", ["レア", "ミディアムレア", "ミディアム", "ウェルダン"]),
        }),
        egg: part("卵（日本の洋食）", {
          omurice: choice("オムライス", ["薄焼き包み", "ふわとろ"]),
          fried_egg_yolk: choice("目玉焼きの黄身", ["半熟", "固焼き"]),
        }),
        tortilla: part("トルティーヤ", {
          type: choice("種類", ["コーン", "小麦"]),
          filling_amount: choice("具の量", ["少なめ", "普通", "多め"]),
          salsa: flag("サルサあり"),
          guacamole: flag("ワカモレあり"),
        }),
        garnish: part("付け合わせ", {
          types: multi("種類", ["パン", "ポテト（フライ）", "ポテト（マッシュ）", "温野菜", "サラダ", "ライス"]),
        }),
        plating: part("盛り付け", {
          margin: scale("皿の余白", 1, 5, "1 皿いっぱい ／ 5 余白が大きい"),
        }),
        course: part("皿構成", {
          type: choice("コースか（カトラリーの並び・皿の小ささ）", ["単品", "コースの一皿"]),
        }),
      },
    },
  ],
};

// ---------- 8. ファストフード・食堂 ----------

const FAST_FOOD_FORMATS = [
  "バーガー", "サンド", "ホットドッグ", "サラダボウル", "スープ", "プレート・定食", "ビュッフェ", "朝食・ブランチ",
];

const FAST_FOOD: CategoryVocab = {
  formats: FAST_FOOD_FORMATS,
  lineages: [
    "大手バーガーチェーン", "グルメバーガー", "スマッシュバーガー", "デリ・サンドイッチ専門", "サラダ専門", "ファミレス",
    "学食・社食", "ホテルビュッフェ", "ブランチ専門店", "その他",
  ],
  partTables: [
    {
      formats: FAST_FOOD_FORMATS,
      parts: {
        burger: part("バーガー", {
          bun: choice("バンズ", ["艶のあるバンズ", "ブリオッシュ", "ごま付き", "全粒粉"]),
          patty_count: count("パティの枚数"),
          patty_style: choice("パティの厚み", ["スマッシュの薄焼き", "厚手"]),
          patty_browning: scale("パティの焼き色", 1, 5, "1 淡い ／ 5 濃い"),
          cheese_slices: count("チーズの枚数"),
          cheese_melting: flag("チーズが溶けて垂れている"),
          layer_count: count("具の層の数"),
          height: choice("高さ", ["低", "中", "高"]),
          sauce: scale("ソース", 0, 4, "0 はみ出しなし ／ 4 垂れる"),
        }),
        sandwich: part("サンド", {
          bread: choice("パン", ["食パン", "バゲット", "チャバタ", "ベーグル", "クロワッサン"]),
          layer_count: count("具の層の数"),
          filling_thickness: choice("パンに対する具の厚み", ["薄い", "パンと同じくらい", "パンより厚い"]),
        }),
        hot_dog: part("ホットドッグ", {
          sausage_thickness: choice("ソーセージの太さ", ["細", "普通", "太"]),
          toppings: multi("トッピング", ["オニオン", "チリ", "ザワークラウト", "マスタード"]),
        }),
        salad_bowl: part("サラダボウル", {
          leaf_ratio: ratio("葉物の比率"),
          proteins: tags("タンパク質の種類", ["鶏", "ツナ", "卵", "豆腐"]),
          topping_count: count("トッピング数"),
          dressing: choice("ドレッシング", ["白系", "透明", "ごま"]),
        }),
        plate: part("プレート・定食", {
          main_dish: tags("主菜の種類", ["ハンバーグ", "唐揚げ", "焼き魚"]),
          item_count: count("品数"),
        }),
        buffet: part("ビュッフェ", {
          item_count: count("品数"),
          bias: choice("偏り", ["肉中心", "野菜中心", "デザート中心", "偏りなし"]),
        }),
        breakfast: part("朝食・ブランチ", {
          main: choice("主役", ["パンケーキ", "フレンチトースト", "エッグベネディクト", "トースト", "和朝食"]),
          egg: choice("卵", [
            "目玉焼き（半熟）", "目玉焼き（固焼き）", "スクランブル（ふわとろ）", "スクランブル（固め）", "ポーチド",
          ]),
        }),
        fries: part("ポテト", {
          cut: choice("切り方", ["細切り", "太切り", "皮付き・ウェッジ"]),
          amount: choice("量", ["少なめ", "普通", "多め"]),
        }),
        packaging: part("包装", {
          type: choice("種類", ["包み紙", "紙箱", "トレー", "陶器の皿"]),
        }),
      },
    },
  ],
};

// ---------- 9. カフェ・喫茶 ----------

const CAFE_FORMATS = ["ドリンクのみ", "ドリンク＋フード", "フード中心"];

const CAFE: CategoryVocab = {
  formats: CAFE_FORMATS,
  lineages: [
    "純喫茶", "大手チェーン", "スペシャルティ・サードウェーブ", "自家焙煎店", "日本茶カフェ", "中国茶・台湾茶",
    "ジューススタンド", "アサイー専門", "動物カフェ", "ブックカフェ", "その他",
  ],
  partTables: [
    {
      formats: CAFE_FORMATS,
      parts: {
        drink: part("ドリンク", {
          type: choice("種類", [
            "ドリップ・ブラック", "エスプレッソ", "ラテ・カプチーノ", "フラッペ系", "紅茶", "抹茶・日本茶", "中国茶・台湾茶",
            "ジュース・スムージー", "クリームソーダ",
          ]),
          temperature: choice("温度", ["ホット", "アイス"]),
          milk: choice("ミルク（色の明るさ）", ["なし", "少し", "多い"]),
          latte_art: choice("ラテアート", ["なし", "ハート・リーフ", "立体・キャラクター"]),
          sweet_toppings: scale("甘い要素", 0, 4, "0 なし ／ 4 ホイップ・シロップ・トッピングが山盛り"),
          cup: choice("器", ["カップ＆ソーサー", "マグ", "ガラス", "紙カップ（無地）", "紙カップ（ロゴ入り）"]),
        }),
        food: part("フード", {
          types: multi("種類", [
            "厚切りトースト", "ナポリタン", "ホットケーキ", "プリン", "サンド", "ケーキ", "アサイーボウル", "焼き菓子",
          ]),
          retro: scale("喫茶度", 1, 5, "1 現代的な盛り付け ／ 5 昔ながらの喫茶店の姿"),
        }),
        space: part("空間", {
          lighting: scale("照明", 1, 5, "1 暗め・間接照明 ／ 5 明るい自然光"),
          interior: choice("内装", ["レトロ（木・ベロア）", "ミニマル（白・コンクリート）", "北欧", "インダストリアル", "和"]),
          seat: choice("席", ["カウンター", "テーブル", "ソファ", "テラス"]),
          usage: choice("過ごし方の手がかり", ["作業（PC・本・ノート）", "会話（向かいにもカップ）"]),
        }),
        animals: part("動物", {
          type: choice("種類", ["猫", "犬", "その他"]),
        }),
      },
    },
  ],
};

// ---------- 10. パン ----------

const BAKERY_FORMATS = ["単品", "トレーに複数（購入時）", "イートイン"];

const BAKERY: CategoryVocab = {
  formats: BAKERY_FORMATS,
  lineages: [
    "ハード系ブーランジェリー", "町のパン屋", "デニッシュ専門", "高級食パン", "ベーグル（ニューヨーク系）",
    "ベーグル（もちもち系）", "サンドイッチ専門", "その他",
  ],
  partTables: [
    {
      formats: BAKERY_FORMATS,
      parts: {
        dough: part("生地", {
          type: choice("系統", [
            "ハード（バゲット・カンパーニュ）", "デニッシュ・クロワッサン", "菓子パン", "惣菜パン", "食パン", "ベーグル", "サンド",
          ]),
          browning: scale("焼き色", 1, 5, "1 白っぽい ／ 5 深い焦げ茶"),
          surface: multi("表面", ["ツヤ（卵塗り）", "粉がけ", "クープ", "ザラメ・砂糖", "ごま・シード"]),
        }),
        crumb: part("断面", {
          bubbles: choice("気泡", ["細かく均一", "大きく不揃い"]),
          layers: scale("層", 0, 4, "0 層なし ／ 4 クロワッサンの層がはっきり"),
        }),
        filling: part("フィリング", {
          type: choice("系統", [
            "なし", "甘い（カスタード・あんこ・チョコ・フルーツ）", "惣菜（カレー・ソーセージ・ツナ・卵・チーズ）",
          ]),
          amount: scale("量", 0, 4, "0 なし ／ 4 生地からあふれる"),
        }),
        size: part("大きさ", {
          size: choice("1個の大きさ", ["小ぶり", "普通", "大きめ"]),
        }),
        purchase: part("購入構成（トレー）", {
          sweet_count: count("甘い系の個数"),
          savory_count: count("惣菜系の個数"),
          hard_count: count("ハード系の個数"),
          total_count: count("合計の個数"),
        }),
        bagel: part("ベーグル", {
          texture: choice("質感", ["ツヤのあるもちもち系", "表面が粗いザクザク系"]),
        }),
      },
    },
  ],
};

// ---------- 11. スイーツ ----------

const SWEETS_FORMATS = [
  "ケーキ（ショート・タルト・ムース・チーズケーキ・ロール・モンブラン）", "焼き菓子", "パフェ", "かき氷", "アイス・ジェラート",
  "ドーナツ", "パンケーキ", "和菓子", "チョコレート",
];

const SWEETS: CategoryVocab = {
  formats: SWEETS_FORMATS,
  lineages: [
    "町のケーキ屋", "パティスリー（フランス菓子）", "映えパフェ", "フルーツパーラー", "甘味処・和菓子", "かき氷専門",
    "ジェラテリア", "ドーナツ専門", "チョコレート専門", "その他",
  ],
  partTables: [
    {
      formats: SWEETS_FORMATS,
      parts: {
        base: part("土台", {
          type: choice("種類", ["スポンジ", "タルト生地", "パイ", "クッキー", "ムース", "チーズ", "餅・求肥", "コーン・カップ"]),
        }),
        flavor: part("主フレーバー", {
          main: choice("系統", [
            "苺", "柑橘", "桃・季節の果物", "チョコ", "キャラメル", "抹茶・ほうじ茶", "ナッツ", "チーズ", "あんこ", "バニラ",
          ]),
        }),
        cream: part("クリーム", {
          type: choice("種類", ["生クリーム", "カスタード", "バタークリーム", "マスカルポーネ", "なし"]),
          amount: scale("量", 0, 4, "0 なし ／ 4 器を覆う"),
        }),
        fruit: part("フルーツ", {
          amount: scale("量", 0, 4, "0 なし ／ 4 フルーツが主役"),
          state: choice("状態", ["生", "コンポート", "焼き"]),
        }),
        finish: part("仕上げ", {
          types: multi("種類", ["鏡面グラサージュ", "粉糖", "キャラメリゼ", "チョコ細工", "金箔", "素朴（飾りなし）"]),
        }),
        sweetness_look: part("甘さの見た目", {
          level: scale("段階", 0, 4, "0 甘い要素が控えめ ／ 4 シロップ・砂糖がけ・チョコが厚い"),
        }),
        cross_section: part("断面", {
          layer_count: count("層の数"),
          shown: flag("断面を見せている"),
        }),
        size: part("大きさ", {
          height: choice("高さ（パフェ・かき氷）", ["器と同じくらい", "器の1.5倍", "器の2倍以上"]),
          piece_size: choice("1ピースの大きさ（ケーキ）", ["小ぶり", "普通", "大きめ"]),
        }),
        temperature: part("温度", {
          state: choice("状態", ["冷たい", "常温", "温かい（焼きたて・溶けかけ）"]),
        }),
        ice_cream: part("アイス", {
          scoop_count: count("球の数"),
          container: choice("容器", ["コーン", "カップ"]),
        }),
        donut: part("ドーナツ", {
          dough: choice("生地", ["イースト（ふんわり）", "ケーキ（ずっしり）", "もちもち"]),
          glaze: flag("グレーズあり"),
        }),
      },
    },
  ],
};

// ---------- 12. 居酒屋・バー ----------
// 飲酒量や頻度は推定しない。お酒は種類だけを記録する。

const IZAKAYA_FORMATS = ["お酒のみ", "料理のみ", "卓全体"];

const IZAKAYA: CategoryVocab = {
  formats: IZAKAYA_FORMATS,
  lineages: [
    "大衆居酒屋", "立ち飲み", "焼き鳥・もつ焼き", "海鮮居酒屋", "創作居酒屋", "日本酒バル", "クラフトビール", "ワインバー",
    "オーセンティックバー", "スポーツバー", "パブ", "その他",
  ],
  partTables: [
    {
      formats: IZAKAYA_FORMATS,
      parts: {
        alcohol: part("お酒", {
          types: multi("種類", [
            "ビール", "クラフトビール", "ハイボール", "サワー・チューハイ", "日本酒", "焼酎", "ワイン（赤）", "ワイン（白）",
            "ワイン（泡）", "カクテル", "ウイスキー", "ノンアルコール",
          ]),
        }),
        beer: part("ビール", {
          color: choice("色", ["ペール", "アンバー", "黒"]),
          cloudy: flag("濁りあり"),
          glass: choice("器", ["ジョッキ", "パイント", "チューリップ型グラス"]),
        }),
        sake: part("日本酒", {
          vessel: choice("器", ["升＋グラス", "徳利・お猪口", "ワイングラス", "片口"]),
        }),
        cocktail: part("カクテル", {
          colors: tags("色", ["赤", "青", "琥珀"]),
          style: choice("グラス", ["ショート", "ロング"]),
          garnish: tags("ガーニッシュ", ["果物", "ハーブ"]),
        }),
        snacks: part("つまみ", {
          dish_count: count("卓上の料理の数"),
          types: multi("系統", ["揚げ物", "焼き物・串", "刺身・海鮮", "珍味・小鉢", "チーズ・生ハム", "ナッツ・乾き物"]),
        }),
        table: part("卓", {
          serving: choice("盛り方", ["大皿シェア", "個皿"]),
          otoshi: tags("お通しの内容", ["枝豆", "煮物", "キャベツ"]),
        }),
        space: part("空間", {
          lighting: scale("照明", 1, 5, "1 暗いバー ／ 5 明るい大衆店"),
          seat: choice("席", ["立ち飲み", "カウンター", "テーブル", "座敷", "テラス・ビアガーデン"]),
          interior: choice("内装", [
            "大衆（短冊メニュー・提灯）", "和モダン", "パブ（木・ビールタップ）", "オーセンティック（バックバー）",
          ]),
        }),
      },
    },
  ],
};

/** カテゴリ名は PlaceCategoryClassifier.categoryRules（= store.category）と同じ。 */
export const CATEGORIES: Record<string, CategoryVocab> = {
  "和食": WASHOKU,
  "ラーメン・麺類": RAMEN,
  "焼肉・肉料理": YAKINIKU,
  "中華": CHUKA,
  "カレー": CURRY,
  "アジア・エスニック": ASIAN,
  "洋食・西洋料理": WESTERN,
  "ファストフード・食堂": FAST_FOOD,
  "カフェ・喫茶": CAFE,
  "パン": BAKERY,
  "スイーツ": SWEETS,
  "居酒屋・バー": IZAKAYA,
  // 部品表を持たない。format / lineage / parts は null とし、common と caption だけ出力する。
  "その他": { formats: [], lineages: [], partTables: [] },
};
