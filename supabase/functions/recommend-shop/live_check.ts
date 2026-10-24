import { createRecommendationHandler } from "./recommendation.ts";
import { configuredKey, loadLocalAPIKeys } from "./local_config.ts";

// Exercise the production recommendation pipeline with real Google calls.
// Auth and history are local fixtures; this does not test a deployed Supabase.
export async function runLiveCheck(
  input: unknown,
  history: unknown[],
  env: (name: string) => string | undefined,
  googleFetch: typeof fetch = fetch,
): Promise<Response> {
  for (const name of ["GEMINI_API_KEY", "GOOGLE_PLACES_API_KEY"]) {
    if (!configuredKey(env(name))) {
      throw new Error(
        `${name}をSwift設定ファイル、または環境変数に設定してください。`,
      );
    }
  }
  const fixtureOrigin = "https://recommendation-fixture.invalid";
  const handler = createRecommendationHandler({
    env: (name) => {
      if (name === "SUPABASE_URL") return fixtureOrigin;
      if (name === "SUPABASE_ANON_KEY") return "local-fixture-key";
      return env(name);
    },
    fetch: (url, options) => {
      const target = new URL(String(url));
      if (target.origin === fixtureOrigin) {
        if (target.pathname === "/auth/v1/user") {
          return Promise.resolve(Response.json({
            id: "11111111-1111-1111-1111-111111111111",
            role: "authenticated",
          }));
        }
        if (target.pathname === "/rest/v1/store") {
          return Promise.resolve(Response.json(history));
        }
        throw new Error("Unexpected fixture request");
      }
      if (
        !["generativelanguage.googleapis.com", "places.googleapis.com"]
          .includes(
            target.hostname,
          ) || target.protocol !== "https:"
      ) throw new Error("Unexpected external service");
      return googleFetch(url, options);
    },
  });
  return await handler(
    new Request(`${fixtureOrigin}/functions/v1/recommend-shop`, {
      method: "POST",
      headers: {
        Authorization: "Bearer local-fixture-token",
        "Content-Type": "application/json",
      },
      body: JSON.stringify(input),
    }),
  );
}

if (import.meta.main) {
  try {
    const [inputPath, historyPath] = Deno.args;
    if (!inputPath || Deno.args.length > 2) {
      throw new Error(
        "使い方: live_check.ts <入力JSONファイル> [履歴JSONファイル]",
      );
    }
    const input: unknown = JSON.parse(await Deno.readTextFile(inputPath));
    const history: unknown = historyPath
      ? JSON.parse(await Deno.readTextFile(historyPath))
      : [];
    if (!Array.isArray(history)) {
      throw new Error("履歴JSONは配列にしてください。");
    }
    const started = performance.now();
    const config = await loadLocalAPIKeys(
      (name) => Deno.env.get(name),
      (url) => Deno.readTextFile(url),
    );
    const response = await runLiveCheck(
      input,
      history,
      config,
    );
    console.log(JSON.stringify(
      {
        history_source: historyPath ? "local_fixture" : "empty",
        status: response.status,
        elapsed_ms: Math.round(performance.now() - started),
        result: await response.json(),
      },
      null,
      2,
    ));
    if (!response.ok) Deno.exitCode = 1;
  } catch (error) {
    // Google failures are sanitized by the handler. CLI failures contain no key.
    const message = error instanceof Error &&
        /^(GEMINI_API_KEY|GOOGLE_PLACES_API_KEY|使い方:|履歴JSON)/.test(
          error.message,
        )
      ? error.message
      : "入力ファイル・JSON形式・Deno実行権限を確認してください。";
    console.error(message);
    Deno.exitCode = 1;
  }
}
