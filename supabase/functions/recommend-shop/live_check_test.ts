import { runLiveCheck } from "./live_check.ts";

Deno.test("live CLI checks missing credentials before making a paid request", async () => {
  let called = false;
  try {
    await runLiveCheck({}, [], () => undefined, () => {
      called = true;
      throw new Error("Must not call Google");
    });
    throw new Error("Expected missing credentials");
  } catch (error) {
    if (
      !(error instanceof Error) || !error.message.startsWith("GEMINI_API_KEY")
    ) {
      throw error;
    }
  }
  if (called) throw new Error("Google called without credentials");
});

Deno.test("live CLI uses local Auth/history, forwards Google calls and keeps output contract", async () => {
  const hosts: string[] = [];
  const response = await runLiveCheck(
    { genre: "カフェ", latitude: 35, longitude: 139 },
    [],
    () => "test-key",
    (url) => {
      const target = new URL(String(url));
      hosts.push(target.hostname);
      if (target.hostname === "generativelanguage.googleapis.com") {
        return Promise.resolve(
          Response.json({
            candidates: [{
              finishReason: "STOP",
              content: {
                parts: [{
                  text: JSON.stringify({
                    search_query: "カフェ",
                    preference_keywords: [],
                  }),
                }],
              },
            }],
          }),
        );
      }
      const shop = {
        id: "verified-place",
        displayName: { text: "カフェ" },
        location: { latitude: 35, longitude: 139 },
        types: ["cafe"],
        googleMapsUri: "https://maps.google.com/?cid=123",
      };
      return Promise.resolve(
        Response.json(
          target.pathname.endsWith(":searchText") ? { places: [shop] } : shop,
        ),
      );
    },
  );
  const result = await response.json();
  if (
    response.status !== 200 ||
    result.recommendation.place_id !== "verified-place" ||
    hosts.join(",") !==
      "generativelanguage.googleapis.com,places.googleapis.com,places.googleapis.com"
  ) {
    throw new Error("Unexpected live-check request routing or response");
  }
});
