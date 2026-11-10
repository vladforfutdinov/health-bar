// Serves the gh-pages branch (Sparkle appcast) on healthbar.forfutdinov.com.
const ORIGIN = "https://raw.githubusercontent.com/vladforfutdinov/health-bar/gh-pages";
const TYPES = { xml: "application/xml; charset=utf-8", html: "text/html; charset=utf-8" };

export default {
  async fetch(request) {
    const path = new URL(request.url).pathname;
    const file = path === "/" ? "/appcast.xml" : path;
    if (file.includes("..")) return new Response("Bad Request", { status: 400 });

    const upstream = await fetch(ORIGIN + file, { cf: { cacheTtl: 60 } });
    if (!upstream.ok) return new Response("Not Found", { status: 404 });

    const ext = file.split(".").pop();
    return new Response(upstream.body, {
      headers: {
        "content-type": TYPES[ext] ?? "application/octet-stream",
        "cache-control": "public, max-age=60",
      },
    });
  },
};
