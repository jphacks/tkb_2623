// vocab（語彙）から、Gemini に渡す JSON Schema と指示文を作る。

import {
  type Attribute,
  CATEGORIES,
  COMMON_PARTS,
  EXTRACTION_RULES,
  type Part,
} from "./vocab/v1.ts";

type JsonSchema = Record<string, unknown>;

function attributeSchema(attribute: Attribute): JsonSchema {
  switch (attribute.kind) {
    case "choice":
      return attribute.multiple
        ? {
          type: ["array", "null"],
          description: attribute.label,
          items: { type: "string", enum: attribute.options },
        }
        : { type: ["string", "null"], description: attribute.label, enum: [...attribute.options, null] };
    case "scale":
      return {
        type: ["integer", "null"],
        description: `${attribute.label}（${attribute.min}〜${attribute.max}: ${attribute.criteria}）`,
        minimum: attribute.min,
        maximum: attribute.max,
      };
    case "count":
      return { type: ["integer", "null"], description: attribute.label, minimum: 0 };
    case "ratio":
      return { type: ["number", "null"], description: `${attribute.label}（0〜1）`, minimum: 0, maximum: 1 };
    case "tags":
      return {
        type: ["array", "null"],
        description: `${attribute.label}（例: ${attribute.examples.join("、")}）`,
        items: { type: "string" },
      };
    case "boolean":
      return { type: ["boolean", "null"], description: attribute.label };
  }
}

/** 部品の集まりを object の schema にする。部品は写っていなければ null。 */
function partsSchema(parts: Record<string, Part>, nullable: boolean): JsonSchema {
  const properties = Object.fromEntries(
    Object.entries(parts).map(([key, part]) => [
      key,
      {
        type: ["object", "null"],
        description: part.label,
        properties: Object.fromEntries(
          Object.entries(part.attributes).map(([attrKey, attr]) => [attrKey, attributeSchema(attr)]),
        ),
        required: Object.keys(part.attributes),
        additionalProperties: false,
      },
    ]),
  );
  return {
    type: nullable ? ["object", "null"] : "object",
    properties,
    required: Object.keys(parts),
    additionalProperties: false,
  };
}

/** カテゴリ（store.category）に対応する出力の JSON Schema。 */
export function buildResponseSchema(category: string): JsonSchema {
  const vocab = CATEGORIES[category];
  if (!vocab) {
    throw new Error(`未知のカテゴリです: ${category}`);
  }

  const hasParts = vocab.partTables.length > 0;
  const nullOnly = { type: "null" };

  // 和食のように部品表が複数あるカテゴリは、形式に合った表を1つ選ばせる。
  const tableSchemas = vocab.partTables.map((table) => ({
    ...partsSchema(table.parts, false),
    description: `形式が ${table.formats.join(" / ")} のときに使う部品表`,
  }));
  const parts = !hasParts
    ? nullOnly
    : tableSchemas.length === 1
    ? { ...tableSchemas[0], type: ["object", "null"] }
    : { anyOf: [...tableSchemas, nullOnly] };

  return {
    type: "object",
    properties: {
      category: { type: "string", enum: [category] },
      format: hasParts ? { type: ["string", "null"], enum: [...vocab.formats, null] } : nullOnly,
      lineage: hasParts ? { type: ["string", "null"], enum: [...vocab.lineages, null] } : nullOnly,
      parts,
      common: partsSchema(COMMON_PARTS, false),
      caption: { type: "string", description: "料理の見た目の短い説明（日本語・1〜2文）" },
    },
    required: ["category", "format", "lineage", "parts", "common", "caption"],
    additionalProperties: false,
  };
}

/** Gemini への指示文（system_instruction）。 */
export function buildSystemInstruction(): string {
  return [
    "あなたは料理写真から見た目の特徴を記録するアシスタントです。",
    "写真の主役の料理1つについて、指定された JSON Schema の形で記述してください。",
    "主役以外の料理（餃子・ライスなど）は common.surroundings.side に入れてください。",
    "各項目の description に書かれた判定基準に従ってください。",
    "",
    "ルール:",
    ...EXTRACTION_RULES.map((rule) => `- ${rule}`),
  ].join("\n");
}

/** ユーザー入力として渡す文。カテゴリは DB の値をそのまま使う。 */
export function buildUserPrompt(category: string): string {
  return `この写真の料理のカテゴリは「${category}」です。このカテゴリとして記述してください。`;
}
