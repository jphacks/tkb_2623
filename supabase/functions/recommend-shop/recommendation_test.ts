import {
  createRecommendationHandler,
  distanceMeters,
} from "./recommendation.ts";

function assert(value: unknown, message = "Assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
function equal(actual: unknown, expected: unknown) {
  assert(
    JSON.stringify(actual) === JSON.stringify(expected),
    `${JSON.stringify(actual)} != ${JSON.stringify(expected)}`,
  );
}

const USER = "11111111-1111-1111-1111-111111111111";
const origin = { latitude: 35, longitude: 139 };
type Data = Record<string, unknown>;
type RequestBody = {
  contents: { parts: { text: string }[] }[];
  textQuery: string;
  pageSize: number;
  locationBias: {
    circle: { center: { latitude: number; longitude: number }; radius: number };
  };
};
function place(id = "new-shop", changes: Data = {}): Data {
  return {
    id,
    displayName: { text: `店舗 ${id}` },
    location: origin,
    types: ["restaurant"],
    businessStatus: "OPERATIONAL",
    rating: 4,
    googleMapsUri: `https://maps.google.com/?q=${id}`,
    ...changes,
  };
}
function area(id: string, latitude = 36): Data {
  return place(id, {
    location: { latitude, longitude: 140 },
    types: ["train_station"],
    formattedAddress: `住所 ${id}`,
  });
}
function atDistance(meters: number) {
  return {
    latitude: origin.latitude + meters / 6371000 * 180 / Math.PI,
    longitude: origin.longitude,
  };
}
interface FixtureOptions {
  history?: unknown[];
  places?: Data[];
  areas?: Data[];
  details?: Record<string, Data | number>;
  analysis?: unknown;
  geminiText?: string;
  authStatus?: number;
  authUser?: Data;
  failure?: string;
  failureStatus?: number;
  malformedService?: string;
  slowService?: string;
  delayMs?: number;
  requestTimeoutMs?: number;
  totalTimeoutMs?: number;
}
function fixture(options: FixtureOptions = {}) {
  const calls: { url: URL; init: RequestInit; body: RequestBody }[] = [];
  const env: Record<string, string> = {
    SUPABASE_URL: "https://supabase.test",
    SUPABASE_ANON_KEY: "anon-test",
    GEMINI_API_KEY: "secret-gemini",
    GOOGLE_PLACES_API_KEY: "secret-places",
  };
  const fetcher: typeof fetch = async (input, init = {}) => {
    const url = new URL(String(input));
    const body = init.body ? JSON.parse(String(init.body)) : {};
    calls.push({ url, init, body });
    const service = url.pathname.includes("/auth/")
      ? "auth"
      : url.pathname.includes("/rest/")
      ? "history"
      : url.hostname === "generativelanguage.googleapis.com"
      ? "gemini"
      : url.pathname.endsWith(":searchText")
      ? "search"
      : "details";
    if (options.slowService === service || options.slowService === "all") {
      await new Promise<void>((resolve, reject) => {
        const signal = init.signal;
        const aborted = () => {
          clearTimeout(timer);
          signal?.removeEventListener("abort", aborted);
          reject(new DOMException("Aborted", "AbortError"));
        };
        const timer = setTimeout(() => {
          signal?.removeEventListener("abort", aborted);
          resolve();
        }, options.delayMs ?? 100);
        signal?.addEventListener("abort", aborted, { once: true });
        if (signal?.aborted) aborted();
      });
    }
    if (options.failure === service) {
      return new Response(
        "secret-gemini secret-places Bearer test-token private memo",
        { status: options.failureStatus ?? 503 },
      );
    }
    if (options.malformedService === service) return new Response("not json");
    if (service === "auth") {
      return Response.json(
        options.authUser ?? { id: USER, role: "authenticated" },
        { status: options.authStatus ?? 200 },
      );
    }
    if (service === "history") return Response.json(options.history ?? []);
    if (service === "gemini") {
      const analysis = options.analysis ??
        { search_query: "ラーメン", preference_keywords: ["あっさり"] };
      return Response.json({
        candidates: [{
          finishReason: "STOP",
          content: {
            parts: [{ text: options.geminiText ?? JSON.stringify(analysis) }],
          },
        }],
      });
    }
    if (service === "search") {
      return Response.json({
        places: body.textQuery === "検索地名"
          ? options.areas ?? []
          : options.places ?? [place()],
      });
    }
    const id = decodeURIComponent(url.pathname.split("/").at(-1)!);
    const detail = options.details?.[id] ??
      (options.places ?? [place()]).find((item) => item.id === id) ?? 404;
    return typeof detail === "number"
      ? new Response(null, { status: detail })
      : Response.json(detail);
  };
  const handler = createRecommendationHandler({
    env: (name) => env[name],
    fetch: fetcher,
    requestTimeoutMs: options.requestTimeoutMs,
    totalTimeoutMs: options.totalTimeoutMs,
  });
  async function invoke(
    input: unknown = { genre: "ラーメン", ...origin },
    authorization: string | null = "Bearer test-token",
  ) {
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
    };
    if (authorization !== null) headers.Authorization = authorization;
    const response = await handler(
      new Request("https://edge.test/recommend-shop", {
        method: "POST",
        headers,
        body: JSON.stringify(input),
      }),
    );
    return { response, data: await response.json() };
  }
  return { invoke, calls, handler, env };
}

Deno.test("success uses Auth identity, own ordered history and verified Places fields only", async () => {
  const f = fixture({
    history: [{
      name: "過去の店",
      category: "ラーメン・麺類",
      reputation: 4.5,
      repeat_num: 3,
      memo: "🍜".repeat(1001),
    }],
    details: {
      "new-shop": place("new-shop", {
        displayName: { text: "詳細の正式店名" },
        location: atDistance(10),
        attributions: [{
          provider: "提供者",
          providerUri: "https://provider.test/",
        }],
      }),
    },
  });
  const { response, data } = await f.invoke({
    genre: "ラーメン",
    ...origin,
    user_id: "attacker",
  });
  equal(response.status, 200);
  equal(Object.keys(data).sort(), [
    "attributions",
    "recommendation",
  ]);
  equal(Object.keys(data.recommendation).sort(), [
    "latitude",
    "longitude",
    "name",
    "place_id",
  ]);
  equal(data.recommendation, {
    place_id: "new-shop",
    name: "詳細の正式店名",
    ...atDistance(10),
  });
  equal(data.attributions.length, 2);
  const history = f.calls[1];
  equal(history.url.searchParams.get("user_id"), `eq.${USER}`);
  equal(history.url.searchParams.get("limit"), "100");
  equal(
    history.url.searchParams.get("order"),
    "reputation.desc.nullslast,repeat_num.desc,created_at.desc,id.asc",
  );
  equal(
    new Headers(history.init.headers).get("Authorization"),
    "Bearer test-token",
  );
  const gemini = f.calls.find((call) =>
    call.url.hostname === "generativelanguage.googleapis.com"
  )!;
  const sent = JSON.parse(gemini.body.contents[0].parts[0].text);
  equal([...sent.history[0].memo].length, 1000);
  equal(sent.history[0].category, "ラーメン・麺類");
  assert(
    history.url.searchParams.get("category")?.startsWith(
      'in.("ラーメン・麺類"',
    ),
  );
  equal(Object.keys(sent).sort(), ["genre", "history"]);
  assert(!("tools" in gemini.body));
  equal(
    f.calls.filter((call) =>
      call.url.hostname === "generativelanguage.googleapis.com"
    ).length,
    1,
  );
  equal(response.headers.get("Cache-Control"), "no-store");
});

Deno.test("empty history uses only genre; blank area does not geocode", async () => {
  const f = fixture();
  const { response } = await f.invoke({
    genre: "ラーメン",
    ...origin,
    area: " \n ",
  });
  equal(response.status, 200);
  const searches = f.calls.filter((call) =>
    call.url.pathname.endsWith(":searchText")
  );
  equal(searches.length, 1);
  equal(searches[0].body.textQuery, "ラーメン");
  equal(searches[0].body.locationBias.circle, { center: origin, radius: 2000 });
  equal(searches[0].body.pageSize, 20);
});

Deno.test("history is filtered by genre before the 100-row prompt limit and excludes null categories", async () => {
  const f = fixture({
    history: [
      ...Array.from(
        { length: 101 },
        () => ({
          name: "unrelated",
          category: "カフェ・喫茶",
          memo: "do not send",
        }),
      ),
      { name: "unknown", category: null },
      { name: "old-label", category: "ラーメン", reputation: null, memo: null },
      { name: "current-label", category: "ラーメン・麺類", reputation: 5 },
    ],
  });
  equal((await f.invoke()).response.status, 200);
  const gemini = f.calls.find((call) =>
    call.url.hostname === "generativelanguage.googleapis.com"
  )!;
  const sent = JSON.parse(gemini.body.contents[0].parts[0].text);
  equal(sent.history.map((row: { name: string }) => row.name), [
    "old-label",
    "current-label",
  ]);
  equal(sent.history[0].reputation, null);
  assert(!JSON.stringify(sent).includes("do not send"));
});

Deno.test("no matching category uses empty history and does not widen the DB filter", async () => {
  const f = fixture({
    history: [{ name: "unrelated", category: "ラーメン・麺類" }],
  });
  equal((await f.invoke({ genre: "中華", ...origin })).response.status, 200);
  const history = f.calls.find((call) =>
    call.url.pathname === "/rest/v1/store"
  )!;
  assert(history.url.searchParams.get("category")?.startsWith('in.("中華"'));
  const gemini = f.calls.find((call) =>
    call.url.hostname === "generativelanguage.googleapis.com"
  )!;
  equal(JSON.parse(gemini.body.contents[0].parts[0].text).history, []);
  equal(
    f.calls.filter((call) => call.url.pathname === "/rest/v1/store").length,
    1,
  );
});

Deno.test("three extracted image attributes affect search and selection even without matching visits", async () => {
  const f = fixture({
    history: [{ name: "unrelated", category: "カフェ・喫茶" }],
    analysis: {
      search_query: "あっさりした鶏のラーメン",
      preference_keywords: ["あっさり", "静か", "鶏"],
    },
    places: [
      place("near", { rating: 5 }),
      place("matched", {
        rating: 4,
        location: atDistance(500),
        reviews: [{ text: { text: "あっさりした鶏スープで、静かな店内" } }],
      }),
    ],
  });
  const { response, data } = await f.invoke({
    genre: "ラーメン",
    ...origin,
    preferences: {
      taste: " あっさり ",
      atmosphere: " 静か ",
      ingredients: [" 鶏 ", "鶏"],
    },
  });
  equal(response.status, 200);
  equal(data.recommendation.place_id, "matched");
  const gemini = f.calls.find((call) =>
    call.url.hostname === "generativelanguage.googleapis.com"
  )!;
  const sent = JSON.parse(gemini.body.contents[0].parts[0].text);
  equal(sent.history, []);
  equal(sent.preferences, {
    taste: "あっさり",
    atmosphere: "静か",
    ingredients: ["鶏"],
  });
  const search = f.calls.find((call) =>
    call.url.pathname.endsWith(":searchText")
  )!;
  equal(search.body.textQuery, "あっさりした鶏のラーメン");
});

Deno.test("blank optional image attributes do not invent preferences", async () => {
  const f = fixture();
  equal(
    (await f.invoke({
      genre: "ラーメン",
      ...origin,
      preferences: { taste: " ", atmosphere: "", ingredients: [] },
    })).response.status,
    200,
  );
  const gemini = f.calls.find((call) =>
    call.url.hostname === "generativelanguage.googleapis.com"
  )!;
  assert(!("preferences" in JSON.parse(gemini.body.contents[0].parts[0].text)));
});

Deno.test("invalid image attributes are rejected before any external call", async () => {
  for (
    const preferences of [
      null,
      [],
      "image",
      { taste: 1 },
      { atmosphere: "x".repeat(201) },
      { ingredients: "鶏" },
      { ingredients: [" "] },
      { ingredients: [1] },
      { ingredients: ["x".repeat(101)] },
      { ingredients: Array(11).fill("鶏") },
    ]
  ) {
    const f = fixture();
    equal(
      (await f.invoke({ genre: "ラーメン", ...origin, preferences })).response
        .status,
      400,
    );
    equal(f.calls.length, 0);
  }
});

Deno.test("Auth must validate bearer and authenticated user before Places or Gemini", async () => {
  for (const auth of [null, "Basic xxx", "Bearer "]) {
    const f = fixture();
    equal((await f.invoke(undefined, auth)).response.status, 401);
    equal(f.calls.length, 0);
  }
  for (const status of [401, 403]) {
    const f = fixture({ authStatus: status });
    equal((await f.invoke()).response.status, 401);
    equal(f.calls.length, 1);
  }
  const f = fixture({ authUser: { id: USER, role: "service_role" } });
  equal((await f.invoke()).response.status, 401);
  equal(f.calls.length, 1);
});

Deno.test("rejects invalid JSON, shapes, genre, area and coordinates without outbound requests", async () => {
  const f = fixture();
  for (
    const input of [
      null,
      [],
      {},
      { genre: " " },
      { genre: "x", ...origin, latitude: 91 },
      { genre: "x", ...origin, longitude: "139" },
      { genre: "x", ...origin, area: 5 },
      { genre: "x".repeat(201), ...origin },
      { genre: "x", ...origin, area: "x".repeat(201) },
    ]
  ) {
    equal((await f.invoke(input)).response.status, 400);
  }
  const response = await f.handler(
    new Request("https://edge.test", {
      method: "POST",
      headers: { Authorization: "Bearer token" },
      body: "{",
    }),
  );
  equal(response.status, 400);
  equal(f.calls.length, 0);
  equal((await f.handler(new Request("https://edge.test"))).status, 405);
});

Deno.test("area takes precedence, deduplicates IDs and clusters nearby stations", async () => {
  const f = fixture({
    areas: [area("station"), area("station"), area("metro", 36.001)],
    places: [place("remote", { location: { latitude: 36, longitude: 140 } })],
  });
  equal(
    (await f.invoke({ genre: "ラーメン", ...origin, area: "検索地名" }))
      .response.status,
    200,
  );
  const searches = f.calls.filter((call) =>
    call.url.pathname.endsWith(":searchText")
  );
  assert(!("locationBias" in searches[0].body));
  equal(searches[1].body.locationBias.circle.center, {
    latitude: 36,
    longitude: 140,
  });
});

Deno.test("unknown or ambiguous area returns 422 with candidates and never falls back", async () => {
  for (
    const areas of [[], [place("not-geographic")], [
      area("a"),
      area("b", 36.01),
    ], [area("a"), area("b", 36.004), area("c", 35.996)]]
  ) {
    const f = fixture({ areas });
    const { response, data } = await f.invoke({
      genre: "ラーメン",
      ...origin,
      area: "検索地名",
    });
    equal(response.status, 422);
    if (areas.length > 1) {
      equal(data.error.code, "AREA_AMBIGUOUS");
      equal(data.error.candidates[0], { name: "店舗 a", address: "住所 a" });
    } else equal(data.error.code, "AREA_NOT_FOUND");
    assert(
      !f.calls.some((call) =>
        call.url.hostname === "generativelanguage.googleapis.com"
      ),
    );
    equal(
      f.calls.filter((call) => call.url.pathname.endsWith(":searchText"))
        .length,
      1,
    );
  }
});

Deno.test("malformed or unusable model output returns safe error before searching shops", async () => {
  for (
    const options of [
      { geminiText: "{broken" },
      { analysis: { search_query: "", preference_keywords: [] } },
      { analysis: { search_query: "x", preference_keywords: [1] } },
      {
        analysis: {
          search_query: "x",
          preference_keywords: ["a", "b", "c", "d", "e", "f"],
        },
      },
    ]
  ) {
    const f = fixture(options);
    const { response, data } = await f.invoke();
    equal(response.status, 502);
    equal(data.error.code, "INVALID_AI_RESPONSE");
    assert(
      !f.calls.some((call) => call.url.hostname === "places.googleapis.com"),
    );
  }
});

Deno.test("filters outside radius, closed, non-food and incomplete candidates; no distance expansion", async () => {
  const f = fixture({
    places: [
      place("outside", { location: atDistance(2000.01) }),
      place("closed", { businessStatus: "CLOSED_PERMANENTLY" }),
      place("temporary", { businessStatus: "CLOSED_TEMPORARILY" }),
      place("museum", { types: ["museum"] }),
      place("missing", { location: null }),
      place("bad", { location: { latitude: 100, longitude: 139 } }),
      place("", {}),
      place("no-name", { displayName: {} }),
    ],
  });
  const { response, data } = await f.invoke();
  equal(response.status, 404);
  equal(data.error.code, "NO_RECOMMENDATION");
  assert(!f.calls.some((call) => call.url.pathname.includes("/places/")));
  equal(
    f.calls.filter((call) => call.url.pathname.endsWith(":searchText")).length,
    1,
  );
});

Deno.test("distance boundary includes 2000m and excludes 2000.01m", async () => {
  // Longitude on the equator produces a stable exact 2000m Haversine value.
  const center = { latitude: 0, longitude: 0 };
  const boundary = { latitude: 0, longitude: 2000 / 6371000 * 180 / Math.PI };
  assert(Math.abs(distanceMeters(center, boundary) - 2000) < 1e-9);
  const f = fixture({ places: [place("boundary", { location: boundary })] });
  equal((await f.invoke({ genre: "カフェ", ...center })).response.status, 200);
  const g = fixture({
    places: [
      place("outside", {
        location: { ...boundary, longitude: boundary.longitude * 1.000005 },
      }),
    ],
  });
  equal((await g.invoke({ genre: "カフェ", ...center })).response.status, 404);
});

Deno.test("preferences can select unvisited shop over nearer higher rated shop", async () => {
  const f = fixture({
    history: [{
      name: "old",
      category: "ラーメン・麺類",
      reputation: 5,
      repeat_num: 20,
      memo: "あっさりが好き",
    }],
    places: [
      place("old", { rating: 5 }),
      place("new", {
        rating: 4,
        location: atDistance(1000),
        reviews: [{ text: { text: "あっさりしたスープ" } }],
      }),
    ],
  });
  equal((await f.invoke()).data.recommendation.place_id, "new");
  const gemini = f.calls.find((call) =>
    call.url.hostname === "generativelanguage.googleapis.com"
  )!;
  assert(!JSON.stringify(gemini.body).includes("あっさりしたスープ"));
});

Deno.test("price and category labels count for taste; missing rating renormalizes weights", async () => {
  const f = fixture({
    history: [{ name: "old", category: "ラーメン・麺類" }],
    analysis: {
      search_query: "カフェ",
      preference_keywords: ["安い", "カフェ"],
    },
    places: [
      place("rated", { rating: 5 }),
      place("taste", {
        rating: null,
        priceLevel: "PRICE_LEVEL_INEXPENSIVE",
        primaryTypeDisplayName: { text: "カフェ" },
      }),
    ],
  });
  equal((await f.invoke()).data.recommendation.place_id, "taste");
});

Deno.test("no taste or rating uses distance; exact ties break by Place ID", async () => {
  const f = fixture({
    places: [
      place("z", { rating: null }),
      place("a", { rating: null }),
      place("far", { rating: null, location: atDistance(500) }),
    ],
  });
  equal((await f.invoke()).data.recommendation.place_id, "a");
});

Deno.test("Google rating competes with distance when no history", async () => {
  const f = fixture({
    places: [
      place("near", { rating: 1 }),
      place("good", { rating: 5, location: atDistance(200) }),
    ],
  });
  equal((await f.invoke()).data.recommendation.place_id, "good");
});

Deno.test("details revalidate ID, coordinates, closure and source then advance without retry", async () => {
  const ids = ["a", "b", "c", "d", "e", "f", "g", "h"];
  const f = fixture({
    places: [...ids.map((id) => place(id)), place("a")],
    details: {
      a: 404,
      b: place("wrong-id"),
      c: place("c", { location: atDistance(2001) }),
      d: place("d", { businessStatus: "CLOSED_TEMPORARILY" }),
      e: place("e", { location: null }),
      f: place("f", { googleMapsUri: null }),
      g: 410,
      h: place("h", { displayName: { text: "照合済み" } }),
    },
  });
  equal((await f.invoke()).data.recommendation.name, "照合済み");
  const details = f.calls.filter((call) =>
    call.url.pathname.includes("/places/")
  );
  equal(details.length, 8);
  equal(details.map((call) => call.url.pathname.split("/").at(-1)), ids);
});

for (const service of ["auth", "history", "gemini", "search", "details"]) {
  Deno.test(`${service} failures and malformed response return 502 without credentials or raw bodies`, async () => {
    for (
      const options of [{ failure: service }, { malformedService: service }]
    ) {
      const f = fixture(options);
      const { response, data } = await f.invoke();
      equal(response.status, 502);
      const serialized = JSON.stringify(data);
      for (
        const secret of [
          "secret-gemini",
          "secret-places",
          "test-token",
          "private memo",
          "not json",
        ]
      ) {
        assert(!serialized.includes(secret));
      }
      equal(
        f.calls.filter((call) => call.url.pathname.includes("/places/")).length,
        service === "details" ? 1 : 0,
      );
    }
  });
}

Deno.test("request deadline cancels fetch and returns 504", async () => {
  const f = fixture({ slowService: "gemini", requestTimeoutMs: 5 });
  const { response, data } = await f.invoke();
  equal(response.status, 504);
  equal(data.error.code, "TIMEOUT");
  assert(
    !f.calls.some((call) => call.url.hostname === "places.googleapis.com"),
  );
});

Deno.test("total deadline covers consecutive requests and cancels active work", async () => {
  const f = fixture({
    slowService: "all",
    delayMs: 15,
    requestTimeoutMs: 100,
    totalTimeoutMs: 25,
  });
  const { response } = await f.invoke();
  equal(response.status, 504);
  assert(f.calls.length <= 2);
});

Deno.test("missing server secrets return safe 500", async () => {
  const f = fixture();
  delete f.env.GEMINI_API_KEY;
  const { response, data } = await f.invoke();
  equal(response.status, 500);
  equal(data.error.code, "CONFIGURATION_ERROR");
});

Deno.test("Gemini billing and model availability errors provide actionable safe codes", async () => {
  for (
    const [status, code] of [
      [402, "GEMINI_BILLING_REQUIRED"],
      [404, "GEMINI_MODEL_UNAVAILABLE"],
      [429, "GEMINI_QUOTA_EXCEEDED"],
    ] as const
  ) {
    const f = fixture({ failure: "gemini", failureStatus: status });
    const { response, data } = await f.invoke();
    equal(response.status, 502);
    equal(data.error.code, code);
    const gemini = f.calls.find((call) =>
      call.url.hostname === "generativelanguage.googleapis.com"
    )!;
    equal(
      gemini.url.pathname,
      "/v1beta/models/gemini-3.1-flash-lite:generateContent",
    );
    assert(!JSON.stringify(data).includes("secret-gemini"));
    assert(
      !f.calls.some((call) => call.url.hostname === "places.googleapis.com"),
    );
  }
});
