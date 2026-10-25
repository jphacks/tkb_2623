// 記録写真（image 行）の追加を Database Webhook で受け取り、料理の特徴を抽出して image.dish_features に保存する。
// 設計と設定手順: supabase/DISH_ANALYSIS.md
//
// Webhook は JWT を付けずに呼ぶため、デプロイ時は JWT 検証を無効にする（--no-verify-jwt）。
// 代わりに x-webhook-secret ヘッダーで呼び出し元を確認する。
//
// 必要な Secret（本番はダッシュボードの Edge Functions > Secrets、ローカルは supabase/functions/.env.local）:
//   GEMINI_API_KEY               Google AI Studio で発行した Gemini API キー
//   GEMINI_MODEL                 使う Gemini のモデル（省略時は gemini.ts の DEFAULT_MODEL）
//   ANALYZE_DISH_WEBHOOK_SECRET  Database Webhook に付ける合言葉（x-webhook-secret ヘッダー）
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY は Supabase が自動で設定する。

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { analyzeDishImage, DEFAULT_MODEL } from "./gemini.ts";
import { CATEGORIES, SCHEMA_VERSION } from "./vocab/v1.ts";

// Supabase Edge Runtime が提供するグローバル（応答後も処理を続けるために使う）。
declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void };

const IMAGE_BUCKET = "record-images";

type ImageRow = {
  id: string;
  store_id: string;
  image: string; // record-images 内のオブジェクトパス
};

type WebhookPayload = {
  type: "INSERT" | "UPDATE" | "DELETE";
  table: string;
  record: ImageRow | null;
};

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "method not allowed" }, 405);
  }

  const webhookSecret = Deno.env.get("ANALYZE_DISH_WEBHOOK_SECRET");
  if (!webhookSecret || !timingSafeEqual(req.headers.get("x-webhook-secret") ?? "", webhookSecret)) {
    return json({ error: "unauthorized" }, 401);
  }

  const geminiApiKey = Deno.env.get("GEMINI_API_KEY");
  if (!geminiApiKey) {
    return json({ error: "GEMINI_API_KEY が設定されていません" }, 500);
  }

  let payload: WebhookPayload;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "invalid json" }, 400);
  }
  if (payload.type !== "INSERT" || payload.table !== "image" || !payload.record) {
    return json({ skipped: true });
  }
  const image = payload.record;
  const model = Deno.env.get("GEMINI_MODEL") || DEFAULT_MODEL;

  // dish_features はアプリから書き込まないため、RLS を迂回できる service role で接続する。
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: updated, error } = await supabase
    .from("image")
    .update({ dish_features: null, dish_features_status: "pending" })
    .eq("id", image.id)
    .select("id");
  if (error) {
    return json({ error: error.message }, 500);
  }
  if (updated.length === 0) {
    // Webhook が届く前に写真が削除された。
    return json({ skipped: true });
  }

  // Gemini は1枚に数十秒かかることがあるため、Webhook には先に応答し、解析は裏で続ける。
  EdgeRuntime.waitUntil(analyzeAndSave(supabase, image, geminiApiKey, model));
  return json({ imageId: image.id, status: "pending" }, 202);
});

/** 写真を解析し、結果を image.dish_features に保存する（失敗時は dish_features_status = failed）。 */
async function analyzeAndSave(
  supabase: SupabaseClient,
  image: ImageRow,
  apiKey: string,
  model: string,
): Promise<void> {
  try {
    // カテゴリは登録画面でユーザーが選んだ store.category をそのまま使う。
    const { data: store, error: storeError } = await supabase
      .from("store")
      .select("category")
      .eq("id", image.store_id)
      .single();
    if (storeError) throw new Error(`店舗の取得に失敗しました: ${storeError.message}`);

    const category = store.category as string | null;
    if (!category || !(category in CATEGORIES)) {
      throw new Error(`カテゴリが不正です: ${category}`);
    }

    const { data: file, error: downloadError } = await supabase.storage
      .from(IMAGE_BUCKET)
      .download(image.image);
    if (downloadError) throw new Error(`写真の取得に失敗しました: ${downloadError.message}`);

    const features = await analyzeDishImage({
      apiKey,
      model,
      category,
      image: new Uint8Array(await file.arrayBuffer()),
      mimeType: file.type || "image/jpeg",
    });

    await updateImage(supabase, image.id, {
      dish_features: { schema_version: SCHEMA_VERSION, model, features },
      dish_features_status: "done",
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`analyze-dish failed (image ${image.id}): ${message}`);
    await updateImage(supabase, image.id, { dish_features_status: "failed" });
  }
}

async function updateImage(
  supabase: SupabaseClient,
  imageId: string,
  values: Record<string, unknown>,
): Promise<void> {
  const { error } = await supabase.from("image").update(values).eq("id", imageId);
  if (error) {
    console.error(`image の更新に失敗しました（image ${imageId}）: ${error.message}`);
  }
}

/** 合言葉の比較で、一致した文字数が応答時間から分からないようにする。 */
function timingSafeEqual(a: string, b: string): boolean {
  const encoder = new TextEncoder();
  const left = encoder.encode(a);
  const right = encoder.encode(b);
  let diff = left.length ^ right.length;
  for (let i = 0; i < Math.max(left.length, right.length); i++) {
    diff |= (left[i] ?? 0) ^ (right[i] ?? 0);
  }
  return diff === 0;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
