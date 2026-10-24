// Gemini API（Interactions API）で料理写真から特徴を抽出する。
// https://ai.google.dev/api/interactions

import { encodeBase64 } from "jsr:@std/encoding@1/base64";
import { buildResponseSchema, buildSystemInstruction, buildUserPrompt } from "./schema.ts";

const ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/interactions";
// gemini-3.8-flash は1枚に数分かかり Edge Function の実行時間内に収まらないため、軽量版を使う（2026-10-25 計測）。
export const DEFAULT_MODEL = "gemini-3.1-flash-lite";

export type AnalyzeInput = {
  apiKey: string;
  model?: string;
  category: string;
  image: Uint8Array;
  mimeType: string; // image/jpeg など
};

type InteractionResponse = {
  status?: string;
  steps?: { type: string; content?: { type: string; text?: string }[] }[];
  errors?: { code: string; message: string }[];
  usage?: Record<string, unknown>;
};

export class GeminiError extends Error {}

/** 抽出結果の JSON（vocab のテンプレートの形）を返す。 */
export async function analyzeDishImage(input: AnalyzeInput): Promise<Record<string, unknown>> {
  const response = await fetch(ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-goog-api-key": input.apiKey },
    body: JSON.stringify({
      model: input.model ?? DEFAULT_MODEL,
      store: false,
      system_instruction: buildSystemInstruction(),
      input: [
        { type: "text", text: buildUserPrompt(input.category) },
        { type: "image", data: encodeBase64(input.image), mime_type: input.mimeType },
      ],
      response_format: {
        type: "text",
        mime_type: "application/json",
        schema: buildResponseSchema(input.category),
      },
    }),
  });

  const body = await response.text();
  if (!response.ok) {
    throw new GeminiError(`Gemini API エラー（HTTP ${response.status}）: ${body}`);
  }

  const interaction = JSON.parse(body) as InteractionResponse;
  if (interaction.status !== "completed") {
    throw new GeminiError(`Gemini の処理が完了しませんでした（status: ${interaction.status}）: ${body}`);
  }

  const text = interaction.steps
    ?.filter((step) => step.type === "model_output")
    .flatMap((step) => step.content ?? [])
    .find((content) => content.type === "text")?.text;
  if (!text) {
    throw new GeminiError(`Gemini の応答に結果がありません: ${body}`);
  }
  return JSON.parse(text);
}
