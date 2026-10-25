// Node 24 runtime tests of the actual Edge Function with Supabase/fetch mocked.
// No network or live Supabase project is used. This is not a Deno type check.
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';
import assert from 'node:assert/strict';

const source = readFileSync(new URL('../functions/ai-recommend/index.ts', import.meta.url), 'utf8')
  .replace(/^import .*createClient.*;\n/m, '');
const code = stripTypeScriptTypes(source);
let handler, stores = [], upstreamStatus = 200, upstreamBody = { predictions: [], mode: 'gemini' };
let forwarded;
const client = {
  auth: { getUser: async () => ({ data: { user: { id: 'user-1' } } }) },
  from(table) {
    assert.equal(table, 'store', 'Edge Function must not publish model status');
    const q = {
      select() { return q; }, eq() { return q; }, not() { return q; }, order() { return q; },
      async range() { return { data: stores, error: null }; },
    };
    return q;
  },
  storage: { from() { throw new Error('Recommendation transport must never download photos'); } },
};
runInNewContext(code, {
  Deno: { env: { get: (key) => ({
    SUPABASE_URL: 'https://test.invalid', SUPABASE_ANON_KEY: 'anon',
    AI_BACKEND_URL: 'https://backend.invalid', AI_BACKEND_API_KEY: 'shared',
  })[key] }, serve: (fn) => { handler = fn; } },
  createClient: () => client, Request, Response, Blob, Uint8Array,
  btoa: (value) => Buffer.from(value, 'binary').toString('base64'),
  fetch: async (url, options) => {
    assert.equal(url, 'https://backend.invalid/recommend');
    assert.equal(options.headers['X-API-Key'], 'shared');
    forwarded = JSON.parse(options.body);
    return new Response(JSON.stringify(upstreamBody), { status: upstreamStatus });
  },
});
const request = (body, token = 'jwt') => new Request('https://edge.invalid', {
  method: 'POST', headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
  body: JSON.stringify(body),
});
const wish = { free_text: '和食', lat: 35, lng: 139 };
assert.equal((await handler(request(wish, ''))).status, 401);
assert.equal((await handler(request(null))).status, 400);
assert.equal((await handler(request({ ...wish, lat: 91 }))).status, 400);
// Zero records is now a supported Gemini request.
assert.equal((await handler(request(wish))).status, 200);
assert.equal(forwarded.history.length, 0);
assert.equal(forwarded.user_id, 'user-1');
stores = [{ id: 'p0', category: null, reputation: 4, created_at: '2026-01-01', image: [
  { id: 'late', image: 'late.png', created_at: '2026-02-01',
    dish_features: { schema_version: 'v1', features: { caption: 'late-dish' } }, dish_features_status: 'done' },
  { id: 'pending', image: 'pending.png', created_at: '2026-01-15', dish_features: null, dish_features_status: 'pending' },
  { id: 'first', image: 'first.png', created_at: '2026-01-01',
    dish_features: { schema_version: 'v1', features: { caption: 'first-dish' } }, dish_features_status: 'done' },
] }];
assert.equal((await handler(request(wish))).status, 200);
assert.equal(forwarded.history[0].image_id, 'first');
assert.ok(!('image_base64' in forwarded.history[0]));
assert.ok(!('image_path' in forwarded.history[0]));
// Every analyzed photo's features in registration order, not only the representative photo.
assert.deepEqual(forwarded.history[0].dish_features, [{ caption: 'first-dish' }, { caption: 'late-dish' }]);
assert.equal(forwarded.history[0].review_count, 50);
assert.equal(forwarded.history[0].category, 'その他');
upstreamStatus = 502;
upstreamBody = { detail: 'temporary failure' };
const failed = await handler(request(wish));
assert.equal(failed.status, 502);
assert.equal((await failed.json()).error, 'temporary failure');
// Even for six eligible stores, Edge sends metadata only. Cloud Run decides
// whether a published ML generation exists before resolving Storage photos.
upstreamStatus = 200;
upstreamBody = { predictions: [], mode: 'lightgbm' };
stores = Array.from({ length: 6 }, (_, i) => ({ ...stores[0], id: `p${i}` }));
assert.equal((await handler(request(wish))).status, 200);
assert.equal(forwarded.history.length, 6);
assert.ok(forwarded.history.every((row) => !('image_base64' in row) && !('image_path' in row)));
console.log('Edge Function runtime checks passed (auth, metadata-only transport, dish features, error compatibility).');
