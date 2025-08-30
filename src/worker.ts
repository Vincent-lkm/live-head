export interface Env {
  LIVE_HEAD_DB: D1Database;
  AUTH_TOKEN: string;
  WEBHOOK_URL?: string;
  HISTORY_ENABLED?: string; // "1" par défaut
}

type PushItem = {
  site: string;
  status: number;
  ms: number;
  port: number;
  location?: string | null;
  ts?: number; // ms
};

export default {
  async fetch(req: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(req.url);

    if (url.pathname === "/health") {
      return new Response("ok", { status: 200 });
    }

    if (url.pathname === "/push" && req.method === "POST") {
      if (!isAuthorized(req, env)) {
        return json({ ok: false, error: "unauthorized" }, 401);
      }

      const body = await safeJson(req);
      if (!body) return json({ ok: false, error: "invalid_json" }, 400);

      const items: PushItem[] = Array.isArray(body) ? body : [body];
      const results: any[] = [];
      for (const item of items) results.push(await handleOne(item, env, ctx));

      return json({ ok: true, count: results.length, results });
    }

    // GET /last?site=site.com   -> dernier état en D1
    if (url.pathname === "/last" && req.method === "GET") {
      const site = (url.searchParams.get("site") || "").toLowerCase().trim();
      if (!site) return json({ ok: false, error: "missing_site" }, 400);

      const row = await env.LIVE_HEAD_DB
        .prepare(
          "SELECT status as s, ms, port as p, location as l, cross as x, ts FROM health_last WHERE site=?1"
        )
        .bind(site)
        .first();

      return json({ ok: true, site, data: row || null });
    }

    // GET /dump_last -> tout ou filtré
    if (url.pathname === "/dump_last" && req.method === "GET") {
      // (Optionnel) protèges l’endpoint : décommente pour forcer l’auth
      // if (!isAuthorized(req, env)) return json({ ok:false, error:"unauthorized" }, 401);

      const qp = url.searchParams;

      // status=500,403,301
      const statusParam = qp.get("status");
      const statuses = (statusParam ? statusParam.split(",") : [])
        .map((s) => parseInt(s.trim(), 10))
        .filter((n) => Number.isFinite(n));

      // cross=1|0|true|false
      const crossParam = qp.get("cross");
      const cross =
        crossParam === null
          ? null
          : ["1", "true"].includes(crossParam.toLowerCase())
          ? 1
          : ["0", "false"].includes(crossParam.toLowerCase())
          ? 0
          : null;

      // since/until en ms
      const since = qp.get("since") ? Number(qp.get("since")) : null;
      const until = qp.get("until") ? Number(qp.get("until")) : null;

      // LIKE site
      const siteLike = qp.get("site_like"); // ex: %site.com

      // tri/pagination
      const order = qp.get("order")?.toLowerCase() === "asc" ? "ASC" : "DESC";
      let limit = qp.get("limit") ? parseInt(qp.get("limit")!, 10) : 1000;
      if (!Number.isFinite(limit) || limit <= 0) limit = 1000;
      if (limit > 5000) limit = 5000;
      let offset = qp.get("offset") ? parseInt(qp.get("offset")!, 10) : 0;
      if (!Number.isFinite(offset) || offset < 0) offset = 0;

      // Build SQL + params (anti-injection via bind)
      let sql =
        "SELECT site, status as s, ms, port as p, location as l, cross as x, ts FROM health_last WHERE 1=1";
      const binds: any[] = [];

      if (statuses.length > 0) {
        const placeholders = statuses.map(() => "?").join(",");
        sql += ` AND status IN (${placeholders})`;
        binds.push(...statuses);
      }

      if (cross !== null) {
        sql += " AND cross = ?";
        binds.push(cross);
      }

      if (since !== null && Number.isFinite(since)) {
        sql += " AND ts >= ?";
        binds.push(since);
      }

      if (until !== null && Number.isFinite(until)) {
        sql += " AND ts <= ?";
        binds.push(until);
      }

      if (siteLike) {
        sql += " AND site LIKE ?";
        binds.push(siteLike);
      }

      sql += ` ORDER BY ts ${order} LIMIT ? OFFSET ?`;
      binds.push(limit, offset);

      const res = await env.LIVE_HEAD_DB.prepare(sql).bind(...binds).all();

      return json({ ok: true, count: res.results.length, data: res.results });
    }

    return new Response("Not Found", { status: 404 });
  },
};

function isAuthorized(req: Request, env: Env): boolean {
  const h = req.headers.get("authorization") || "";
  const token = h.toLowerCase().startsWith("bearer ")
    ? h.slice(7).trim()
    : new URL(req.url).searchParams.get("token") || "";
  return !!token && token === env.AUTH_TOKEN;
}

async function safeJson(req: Request): Promise<any | null> {
  try {
    return await req.json();
  } catch {
    return null;
  }
}

function isRedirect(status: number): boolean {
  return status === 301 || status === 302 || status === 307 || status === 308;
}

function hostFromUrl(u?: string | null): string | null {
  if (!u) return null;
  try {
    if (u.startsWith("/")) return null; // relatif => même domaine
    return new URL(u).host.toLowerCase().replace(/\.$/, "");
  } catch {
    return null;
  }
}

function expectedHosts(site: string): string[] {
  const s = site.toLowerCase().replace(/^https?:\/\//, "").replace(/\/.*$/, "");
  const host = s.replace(/\.$/, "");
  const apex = host.startsWith("www.") ? host.slice(4) : host;
  return [apex, `www.${apex}`];
}

function computeCross(site: string, status: number, location?: string | null): boolean {
  if (!isRedirect(status) || !location) return false;
  const target = hostFromUrl(location);
  if (!target) return false; // relatif => pas cross
  const expected = expectedHosts(site);
  return !expected.includes(target);
}

async function handleOne(item: PushItem, env: Env, ctx: ExecutionContext) {
  const now = Date.now();
  const site = String(item.site || "").toLowerCase().trim();
  const status = Number(item.status || 0);
  const ms = Number(item.ms || 0);
  const port = Number(item.port || 0);
  const location = item.location ?? null;
  const ts = Number.isFinite(item.ts) && item.ts! > 0 ? Number(item.ts) : now;

  if (!site || !Number.isFinite(status) || !Number.isFinite(ms)) {
    return { site, ok: false, error: "invalid_fields" };
  }

  const cross = computeCross(site, status, location);

  // 1) D1 upsert "last"
  const updated_at = now;
  await env.LIVE_HEAD_DB
    .prepare(
      `INSERT INTO health_last (site,status,ms,port,location,cross,ts,updated_at)
       VALUES (?1,?2,?3,?4,?5,?6,?7,?8)
       ON CONFLICT(site) DO UPDATE SET
         status=excluded.status,
         ms=excluded.ms,
         port=excluded.port,
         location=excluded.location,
         cross=excluded.cross,
         ts=excluded.ts,
         updated_at=excluded.updated_at`
    )
    .bind(site, status, ms, port, location, cross ? 1 : 0, ts, updated_at)
    .run();

  // 2) Historique (optionnel)
  if ((env.HISTORY_ENABLED ?? "1") !== "0") {
    ctx.waitUntil(
      env.LIVE_HEAD_DB
        .prepare(
          `INSERT INTO health_history (site,status,ms,port,location,cross,ts)
           VALUES (?1,?2,?3,?4,?5,?6,?7)`
        )
        .bind(site, status, ms, port, location, cross ? 1 : 0, ts)
        .run()
    );
  }

  // 3) Alerte
  if (env.WEBHOOK_URL && (status >= 500 || (isRedirect(status) && cross))) {
    ctx.waitUntil(sendAlert(env.WEBHOOK_URL, { site, status, ms, port, location, cross, ts }));
  }

  return { site, ok: true, cross, status };
}

async function sendAlert(webhookUrl: string, p: {
  site: string; status: number; ms: number; port: number; location?: string | null; cross: boolean; ts: number;
}) {
  const when = new Date(p.ts).toISOString();
  const msg = p.cross
    ? `🚨 *Cross-domain redirect* ${p.site} → ${p.location} [${p.status}]`
    : `🔥 *HTTP ${p.status}* sur ${p.site}`;

  const discord = {
    content: msg,
    embeds: [
      {
        title: p.cross ? "Cross-domain redirect détectée" : "Erreur serveur",
        fields: [
          { name: "Site", value: `\`${p.site}\``, inline: true },
          { name: "Status", value: `${p.status}`, inline: true },
          { name: "Latence (ms)", value: `${p.ms}`, inline: true },
          { name: "Port", value: `${p.port}`, inline: true },
          { name: "Location", value: p.location || "—", inline: false },
          { name: "Horodatage", value: when, inline: false },
        ],
      },
    ],
  };

  const slack = {
    text: `${msg}\n• site: ${p.site}\n• status: ${p.status}\n• ms: ${p.ms}\n• port: ${p.port}\n• location: ${p.location || "—"}\n• ts: ${when}`,
  };

  const isDiscord = webhookUrl.includes("discord.com/api/webhooks/");
  const payload = isDiscord ? discord : slack;

  try {
    await fetch(webhookUrl, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
    });
  } catch {
    // silence errors
  }
}

function json(obj: any, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

