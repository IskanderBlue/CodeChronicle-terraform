// Edge proxy: serves CCM-mirrored asset trees (documents/, elaws/, amended/, laws/)
// from R2 on the *app* origin, so the root-relative <img src="/laws/..."> paths
// baked into stored version HTML resolve verbatim — no HTML rewrite, no origin
// round-trip. Bound to R2 via the ASSETS binding (see workers_script in main.tf),
// so this Worker holds no credentials. Routed on app.<domain>/{prefix}/* by the
// cloudflare_workers_route resources.

// Prefixes this Worker will not serve without a valid token. Must match
// SIGNED_PREFIXES in the app's config/assets.py. "documents/" holds the
// whole-page scans of the pre-e-Laws editions — the primary evidence, for an
// edition the app gates — and its keys are sequential, so without this anybody
// could walk a paid edition page by page while never loading a gated page.
// The other mirrored prefixes are figure fragments shared by free and paid
// editions, and laws/ paths are baked into HTML the app renders verbatim.
const SIGNED_PREFIXES = ["documents"];

// Token: first 32 hex characters of HMAC-SHA256(secret, key). Deliberately not
// time-limited — see core/asset_signing.py. An expiring token cannot survive
// the app's conditional responses or a printed exhibit; what this defeats is
// enumeration of a sequential key space, not re-posting of a URL.
const TOKEN_PARAM = "s";
const TOKEN_LENGTH = 32;

let cachedKeyPromise = null;

function hmacKey(secret) {
  if (!cachedKeyPromise) {
    cachedKeyPromise = crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(secret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    );
  }
  return cachedKeyPromise;
}

async function expectedToken(secret, key) {
  const signature = await crypto.subtle.sign(
    "HMAC",
    await hmacKey(secret),
    new TextEncoder().encode(key),
  );
  return [...new Uint8Array(signature)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
    .slice(0, TOKEN_LENGTH);
}

// Length-independent compare, so a mismatch does not leak position by timing.
function constantTimeEquals(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export default {
  async fetch(request, env) {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method Not Allowed", {
        status: 405,
        headers: { allow: "GET, HEAD" },
      });
    }

    // Map the URL path to an R2 key: "/laws/images/x.webp" -> "laws/images/x.webp".
    // The bucket keys carry the prefix, so the mapping is 1:1.
    const url = new URL(request.url);
    const key = decodeURIComponent(url.pathname.replace(/^\/+/, ""));
    if (!key) return new Response("Not Found", { status: 404 });

    if (SIGNED_PREFIXES.includes(key.split("/")[0])) {
      // A missing secret must refuse, never wave things through: a Worker
      // deployed without its binding would otherwise silently un-gate every
      // scan and look perfectly healthy.
      if (!env.ASSET_SIGNING_KEY) {
        return new Response("Forbidden", { status: 403 });
      }
      const supplied = url.searchParams.get(TOKEN_PARAM) || "";
      const expected = await expectedToken(env.ASSET_SIGNING_KEY, key);
      if (!constantTimeEquals(supplied, expected)) {
        return new Response("Forbidden", { status: 403 });
      }
    }

    // Pass conditional/range headers through so R2 can answer 304/206 itself.
    const object = await env.ASSETS.get(key, {
      onlyIf: request.headers,
      range: request.headers,
    });

    if (object === null) {
      return new Response("Not Found", { status: 404 });
    }

    const headers = new Headers();
    object.writeHttpMetadata(headers);
    headers.set("etag", object.httpEtag);
    // Build artifacts are content-addressed and immutable once published.
    headers.set("cache-control", "public, max-age=31536000, immutable");

    // get() with onlyIf returns a bodyless R2Object when the precondition
    // fails (-> 304); otherwise an R2ObjectBody with a streamable body.
    if (!("body" in object) || object.body === undefined) {
      return new Response(null, { status: 304, headers });
    }

    const partial = object.range !== undefined && request.headers.has("range");
    if (partial) {
      const { offset = 0, length = object.size } = object.range;
      headers.set("content-range", `bytes ${offset}-${offset + length - 1}/${object.size}`);
    }
    return new Response(request.method === "HEAD" ? null : object.body, {
      status: partial ? 206 : 200,
      headers,
    });
  },
};
