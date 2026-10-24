// Only the local CLI reads Swift files. Edge Functions continue to use Secrets.
const CONFIGS = {
  GEMINI_API_KEY: "GourmetShareMap/Services/Gemini/GoogleGeminiConfig.swift",
  GOOGLE_PLACES_API_KEY:
    "GourmetShareMap/Services/Places/GoogleMapConfig.swift",
};

export function configuredKey(value: string | undefined): string | undefined {
  const key = value?.trim();
  return key && key !== "replace-with-server-key" && !key.startsWith("YOUR_")
    ? key
    : undefined;
}

export async function loadLocalAPIKeys(
  env: (name: string) => string | undefined,
  readText: (url: URL) => Promise<string>,
): Promise<(name: string) => string | undefined> {
  const keys: Record<string, string> = {};
  for (const [name, path] of Object.entries(CONFIGS)) {
    let key = configuredKey(env(name));
    if (!key) {
      try {
        const source = await readText(
          new URL(`../../../${path}`, import.meta.url),
        );
        // Read an ordinary static string literal without evaluating Swift code.
        // Assignments prefixed with // are ignored. API keys are ASCII strings.
        const literal = source.match(
          /^\s*static\s+let\s+apiKey\s*=\s*("(?:[^"\\\r\n]|\\.)*")\s*(?:\/\/[^\r\n]*)?$/m,
        )?.[1];
        key = literal ? configuredKey(JSON.parse(literal)) : undefined;
      } catch {
        // File paths, source text and raw errors may contain secrets.
        key = undefined;
      }
    }
    if (!key) {
      throw new Error(
        `${name}を${path}のstatic let apiKey、または環境変数に設定してください。`,
      );
    }
    keys[name] = key;
  }
  return (name) => keys[name] ?? env(name);
}
