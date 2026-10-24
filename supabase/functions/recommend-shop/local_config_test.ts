import { loadLocalAPIKeys } from "./local_config.ts";

Deno.test("local CLI loads both Swift config paths without env files", async () => {
  const paths: string[] = [];
  const config = await loadLocalAPIKeys(() => undefined, (url) => {
    paths.push(url.pathname);
    return Promise.resolve(
      `enum Config {\n    static let apiKey = "${
        paths.length === 1 ? "gemini-test-key" : "maps-test-key"
      }"\n}`,
    );
  });
  if (
    config("GEMINI_API_KEY") !== "gemini-test-key" ||
    config("GOOGLE_PLACES_API_KEY") !== "maps-test-key" ||
    !paths[0].endsWith(
      "/GourmetShareMap/Services/Gemini/GoogleGeminiConfig.swift",
    ) ||
    !paths[1].endsWith("/GourmetShareMap/Services/Places/GoogleMapConfig.swift")
  ) {
    throw new Error("Swift config paths or keys do not match");
  }
});

Deno.test("explicit environment keys take precedence over Swift files", async () => {
  const config = await loadLocalAPIKeys(
    (name) => name === "GEMINI_MODEL" ? "test-model" : "env-test-key",
    () => {
      throw new Error("Should not read files");
    },
  );
  if (
    config("GEMINI_API_KEY") !== "env-test-key" ||
    config("GEMINI_MODEL") !== "test-model"
  ) {
    throw new Error("Environment overrides lost");
  }
});

Deno.test("placeholders, comments and unreadable files produce safe configuration errors", async () => {
  for (
    const source of [
      'static let apiKey = "YOUR_GOOGLE_GEMINI_API_KEY"',
      '// static let apiKey = "secret-test-key"',
      'static let apiKey = ""',
      "static let apiKey = loadSecret()",
      null,
    ]
  ) {
    try {
      await loadLocalAPIKeys(() => "replace-with-server-key", () => {
        if (source === null) throw new Error("secret-test-key");
        return Promise.resolve(source);
      });
      throw new Error("Expected configuration error");
    } catch (error) {
      if (
        !(error instanceof Error) ||
        !error.message.startsWith("GEMINI_API_KEY") ||
        error.message.includes("secret-test-key")
      ) throw error;
    }
  }
});
