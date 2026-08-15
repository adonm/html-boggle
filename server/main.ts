/**
 * html-boggle server: static hosting for dist/. That's it.
 *
 * The game has no server component: room discovery happens serverlessly via
 * the public pkarr relays (see glue/glue.js and net/src/lib.rs). This server
 * only exists so you can open the game in a browser during development, or
 * host it on any static file server (GitHub Pages works as-is).
 */

const PORT = Number(Deno.env.get("PORT") ?? 8000);
const DIST = new URL("../dist/", import.meta.url);

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

const MIME: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".wasm": "application/wasm",
  ".json": "application/json",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".css": "text/css; charset=utf-8",
  ".txt": "text/plain; charset=utf-8",
  ".ico": "image/x-icon",
  ".map": "application/json",
};

async function serveStatic(req: Request): Promise<Response> {
  const url = new URL(req.url);
  let path = decodeURIComponent(url.pathname);
  if (path === "/") path = "/index.html";
  const file = new URL(`.${path}`, DIST);
  if (!file.pathname.startsWith(DIST.pathname)) {
    return json({ error: "forbidden" }, 403);
  }
  try {
    const data = await Deno.readFile(file);
    const ext = path.slice(path.lastIndexOf("."));
    return new Response(data, {
      headers: {
        "content-type": MIME[ext] ?? "application/octet-stream",
        "cache-control": "no-store",
      },
    });
  } catch {
    return json({ error: "not found" }, 404);
  }
}

Deno.serve({ port: PORT, hostname: "0.0.0.0" }, async (req) => {
  const url = new URL(req.url);
  if (url.pathname === "/api/health") return json({ ok: true });
  return await serveStatic(req);
});
