// AIレコメンドのプロキシ。iOSはAIバックエンド(Cloud Run)を直接呼ばず、
// このEdge Function経由でアクセスする(APIキーをアプリに埋め込まない)。
//
// 役割: 認証済みユーザーの評価履歴をSupabaseから組み立て、Cloud Runの /recommend に転送する。
// 要件定義: mogumap_clip_lgbm/REQUIREMENTS.md
//
// 必要な環境変数(`supabase secrets set` で設定):
//   AI_BACKEND_URL      Cloud Run サービスのURL(例: https://ai-backend-xxxxx.a.run.app)
//   AI_BACKEND_API_KEY  Cloud Run側の AI_BACKEND_API_KEY と同じ共有シークレット
import { createClient } from "jsr:@supabase/supabase-js@2";

// 0〜5件はGemini、6件以上は学習済みモデル。未学習時はGeminiを継続。

// 新カラム(store.price_level / google_rating / review_count)がNULLの既存データ向けの
// 補完値。要件定義 6章参照。
const DEFAULTS = { price_level: 2, google_rating: 3.5, review_count: 50 };

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "POST only" }), { status: 405 });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "missing Authorization header" }), { status: 401 });
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData?.user) {
    return new Response(JSON.stringify({ error: "invalid session" }), { status: 401 });
  }
  const userId = userData.user.id;

  let body: { free_text?: string; lat?: number; lng?: number };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid JSON body" }), { status: 400 });
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) return jsonError("invalid JSON body", 400);
  const { free_text, lat, lng } = body;
  if (typeof free_text !== "string" || !free_text.trim() || free_text.length > 500
      || typeof lat !== "number" || !Number.isFinite(lat) || Math.abs(lat) > 90
      || typeof lng !== "number" || !Number.isFinite(lng) || Math.abs(lng) > 180) {
    return new Response(
      JSON.stringify({ error: "free_text, lat, lng are required" }),
      { status: 400 },
    );
  }

  // Pagination avoids silently truncating histories at Supabase's default row limit.
  const stores: StoreRow[] = [];
  for (let offset = 0; offset <= 2000; offset += 500) {
    const { data, error } = await supabase.from("store")
      .select("id, category, reputation, price_level, google_rating, review_count, created_at, image(id, image, created_at, dish_features, dish_features_status)")
      .eq("user_id", userId).not("reputation", "is", null)
      .order("id").range(offset, offset + 499);
    if (error) return jsonError("店舗履歴を取得できませんでした", 502);
    stores.push(...(data ?? []));
    if (stores.length > 2000) return jsonError("学習対象の店舗記録は2000件までです", 400);
    if ((data ?? []).length < 500) break;
  }

  type StoreRow = {
    id: string;
    category: string | null;
    reputation: number;
    price_level: number | null;
    google_rating: number | null;
    review_count: number | null;
    created_at: string;
    image: {
      id: string;
      image: string;
      created_at: string;
      dish_features: { features?: Record<string, unknown> } | null;
      dish_features_status: string | null;
    }[] | null;
  };

  // Text-only transport for every recommendation request. The backend downloads
  // history photos from Storage only after it selects a published ML model.
  // Gemini requests never download, encode, or transfer photo bytes.
  const history = stores.filter((store) => store.image?.length).map((store) => {
    const photos = [...store.image!].sort((a, b) =>
      a.created_at.localeCompare(b.created_at) || a.id.localeCompare(b.id));
    return {
      place_id: store.id, image_id: photos[0].id,
      category: store.category ?? "その他", price_level: store.price_level ?? DEFAULTS.price_level,
      google_rating: store.google_rating ?? DEFAULTS.google_rating,
      review_count: store.review_count ?? DEFAULTS.review_count,
      user_id: userId, rating: store.reputation, rated_at: store.created_at,
      dish_features: photos
        .filter((photo) => photo.dish_features_status === "done" && photo.dish_features?.features)
        .map((photo) => photo.dish_features!.features),
    };
  });

  const aiBackendUrl = Deno.env.get("AI_BACKEND_URL");
  const aiBackendApiKey = Deno.env.get("AI_BACKEND_API_KEY");
  if (!aiBackendUrl || !aiBackendApiKey) {
    return new Response(JSON.stringify({ error: "AI backend is not configured" }), { status: 500 });
  }

  let backendResponse: Response;
  try {
    backendResponse = await fetch(`${aiBackendUrl}/recommend`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-API-Key": aiBackendApiKey },
      body: JSON.stringify({ user_id: userId, free_text, lat, lng, history }),
    });
  } catch {
    return jsonError("AIサーバーに接続できませんでした", 502);
  }

  const resultText = await backendResponse.text();

  // Only the training Job publishes model statistics. Preserve iOS error format.
  if (!backendResponse.ok) {
    let message = "おすすめを取得できませんでした";
    try {
      const parsed = JSON.parse(resultText);
      if (typeof parsed.detail === "string") message = parsed.detail;
    } catch { /* generic error */ }
    return jsonError(message, backendResponse.status);
  }
  return new Response(resultText, {
    status: backendResponse.status,
    headers: { "Content-Type": "application/json" },
  });
});

function jsonError(error: string, status: number): Response {
  return new Response(JSON.stringify({ error }), { status, headers: { "Content-Type": "application/json" } });
}
