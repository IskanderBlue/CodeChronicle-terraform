// Edge proxy: serves CCM-mirrored asset trees (documents/, amended/, laws/)
// from R2 on the *app* origin, so the root-relative <img src="/laws/..."> paths
// baked into stored version HTML resolve verbatim — no HTML rewrite, no origin
// round-trip. Bound to R2 via the ASSETS binding (see workers_script in main.tf),
// so this Worker holds no credentials. Routed on app.<domain>/{prefix}/* by the
// cloudflare_workers_route resources.
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
