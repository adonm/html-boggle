/**
 * html-boggle server: static hosting for dist/ plus a tiny room registry.
 *
 * The registry is the only rendezvous mechanism in the game: browsers POST their
 * node id to a room keyed by the (normalized) room code, and get the current
 * member list back. Everything after that - presence, moves, scores - flows
 * end-to-end encrypted over iroh gossip channels (relayed, from browsers).
 *
 * The registry holds no game state, only {nodeId, name, lastSeen} entries that
 * expire after ROOM_TTL_MS without a ping.
 */

const PORT = Number(Deno.env.get("PORT") ?? 8000);
const DIST = new URL("../dist/", import.meta.url);
const ROOM_TTL_MS = 60_000;

type Member = {
  nodeId: string;
  name: string;
  lastSeen: number;
};

const rooms = new Map<string, Map<string, Member>>();

function normRoom(room: unknown): string | null {
  if (typeof room !== "string") return null;
  const r = room.toLowerCase().replace(/[^a-z0-9]/g, "");
  return r.length > 0 && r.length <= 32 ? r : null;
}

function prune(room: Map<string, Member>) {
  const now = Date.now();
  for (const [key, member] of room) {
    if (now - member.lastSeen > ROOM_TTL_MS) room.delete(key);
  }
}

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

async function readJson(req: Request): Promise<Record<string, unknown> | null> {
  try {
    const body = await req.json();
    return body !== null && typeof body === "object" ? (body as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

Deno.serve({ port: PORT, hostname: "0.0.0.0" }, async (req) => {
  const url = new URL(req.url);

  if (req.method === "POST" && url.pathname === "/api/join") {
    const body = await readJson(req);
    const roomCode = normRoom(body?.room);
    const nodeId = typeof body?.nodeId === "string" && body.nodeId.length <= 128
      ? body.nodeId
      : null;
    if (!roomCode || !nodeId) return json({ error: "bad request" }, 400);

    let room = rooms.get(roomCode);
    if (!room) {
      room = new Map();
      rooms.set(roomCode, room);
    }
    prune(room);
    room.set(nodeId, {
      nodeId,
      name: typeof body?.name === "string" ? body.name.slice(0, 40) : "",
      lastSeen: Date.now(),
    });

    const members = [...room.values()]
      .filter((m) => m.nodeId !== nodeId)
      .map((m) => ({ nodeId: m.nodeId, name: m.name }));
    return json({ members });
  }

  if (req.method === "POST" && url.pathname === "/api/ping") {
    const body = await readJson(req);
    const roomCode = normRoom(body?.room);
    const nodeId = typeof body?.nodeId === "string" ? body.nodeId : null;
    const member = roomCode && nodeId ? rooms.get(roomCode)?.get(nodeId) : undefined;
    if (member) member.lastSeen = Date.now();
    return json({ ok: true });
  }

  if (url.pathname === "/api/health") return json({ ok: true });

  return await serveStatic(req);
});
