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
let downloadsFail = false, forwarded, downloaded = [];
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
  storage: { from(bucket) {
    assert.equal(bucket, 'record-images');
    return { async download(path) {
      downloaded.push(path);
      return downloadsFail ? { error: new Error('secret upstream detail') }
        : { data: new Blob(['image-bytes']), error: null };
    } };
  } },
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
  { id: 'late', image: 'late.png', created_at: '2026-02-01' },
  { id: 'first', image: 'first.png', created_at: '2026-01-01' },
] }];
assert.equal((await handler(request(wish))).status, 200);
assert.equal(downloaded.at(-1), 'first.png');
assert.equal(forwarded.history[0].review_count, 50);
assert.equal(forwarded.history[0].category, 'その他');
upstreamStatus = 502;
upstreamBody = { detail: 'temporary failure' };
const failed = await handler(request(wish));
assert.equal(failed.status, 502);
assert.equal((await failed.json()).error, 'temporary failure');
downloadsFail = true;
const storageFailure = await handler(request(wish));
assert.equal(storageFailure.status, 503);
assert.ok(!(await storageFailure.text()).includes('secret upstream'));
console.log('Edge Function runtime checks passed (auth, 0 records, photos, error compatibility, Storage failure).');
