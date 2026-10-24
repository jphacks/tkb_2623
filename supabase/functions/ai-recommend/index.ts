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

// mogumap_clip_lgbm/ml.py の MIN_RECORDS と合わせる(育成タブLv.2の閾値)。
const MIN_RECORDS = 5;
const RECORD_IMAGES_BUCKET = "record-images";

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
  const { free_text, lat, lng } = body;
  if (!free_text || typeof lat !== "number" || typeof lng !== "number") {
    return new Response(
      JSON.stringify({ error: "free_text, lat, lng are required" }),
      { status: 400 },
    );
  }

  // 評価済み(reputationが入っている)店舗を、紐づく画像(先頭1枚)と一緒に取得する。
  const { data: stores, error: storesError } = await supabase
    .from("store")
    .select("id, category, reputation, price_level, google_rating, review_count, created_at, image(id, image)")
    .eq("user_id", userId)
    .not("reputation", "is", null);

  if (storesError) {
    return new Response(JSON.stringify({ error: storesError.message }), { status: 500 });
  }

  type StoreRow = {
    id: string;
    category: string | null;
    reputation: number;
    price_level: number | null;
    google_rating: number | null;
    review_count: number | null;
    created_at: string;
    image: { id: string; image: string }[] | null;
  };

  // 画像のダウンロードはネットワークI/O待ちが大半なので、店舗数分を並列化する
  // (店舗数が多いユーザーで1件ずつ待つと、Cloud Run側の処理時間と合わせてクライアントの
  // タイムアウトを超えることがあった)。
  const storesWithPhotos = (stores ?? []).filter((s: StoreRow) => s.image?.[0]);
  const historyResults = await Promise.all(
    storesWithPhotos.map(async (store: StoreRow) => {
      const firstImage = store.image![0];
      const { data: fileData, error: downloadError } = await supabase.storage
        .from(RECORD_IMAGES_BUCKET)
        .download(firstImage.image);
      if (downloadError || !fileData) return null;

      const bytes = new Uint8Array(await fileData.arrayBuffer());
      return {
        place_id: store.id,
        image_id: firstImage.id,
        image_base64: encodeBase64(bytes),
        category: store.category ?? "その他",
        price_level: store.price_level ?? DEFAULTS.price_level,
        google_rating: store.google_rating ?? DEFAULTS.google_rating,
        review_count: store.review_count ?? DEFAULTS.review_count,
        user_id: userId,
        rating: store.reputation,
        rated_at: store.created_at,
      };
    }),
  );
  const history = historyResults.filter((h): h is Record<string, unknown> => h !== null);

  if (history.length < MIN_RECORDS) {
    return new Response(
      JSON.stringify({ error: `AIを育てるには、あと${MIN_RECORDS - history.length}件お店を登録してください` }),
      { status: 400 },
    );
  }

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
  } catch (e) {
    return new Response(JSON.stringify({ error: `AI backend unreachable: ${e}` }), { status: 502 });
  }

  const resultText = await backendResponse.text();

  if (backendResponse.ok) {
    try {
      const result = JSON.parse(resultText);
      const modelStats = result.model_stats;
      if (modelStats) {
        await supabase.from("ai_model_status").upsert({
          user_id: userId,
          record_count: modelStats.trained_records ?? history.length,
          mean_abs_error: modelStats.mean_abs_error ?? null,
          model_gcs_path: modelStats.model_path ?? null,
          trained_at: new Date().toISOString(),
        });
      }
    } catch {
      // 統計の保存に失敗しても、レコメンド結果自体は返す。
    }
  }

  return new Response(resultText, {
    status: backendResponse.status,
    headers: { "Content-Type": "application/json" },
  });
});

function encodeBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}
