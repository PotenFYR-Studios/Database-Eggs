// Static prerender: renders every route with react-dom/server and injects the
// result (plus per-page title/description/canonical/OG/Twitter meta and the
// landing JSON-LD graph) into the Vite shell, emitting dist/<route>/index.html
// and dist/<route>.html twins so crawlers get full body content and direct
// refreshes keep working.
//
// Runs after `vite build` (see package.json "build"). No extra dependencies:
// react + react-dom only. Values are real site data, never invented.

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createElement, StrictMode } from "react";
import { renderToString } from "react-dom/server";
import App from "../src/App";
import { CANON, PAGES, type PageMeta } from "../src/meta";

const __dir = dirname(fileURLToPath(import.meta.url));
const distDir = resolve(__dir, "..", "dist");

const OG_IMAGE = `${CANON}/og.png`;
const OG_IMAGE_ALT =
  "Database-Eggs: one egg for every database, version and panel";

/**
 * Minimal browser-global stubs: page components read window.location /
 * location.pathname during render (routing, sidebar highlighting). All other
 * browser globals are only touched inside effects, which never run server-side.
 */
function stubBrowser(pathname: string) {
  const host = CANON.replace(/^https?:\/\//, "");
  const location = {
    href: `${CANON}${pathname}`,
    origin: CANON,
    protocol: "https:",
    host,
    hostname: host,
    pathname,
    search: "",
    hash: "",
  };
  const noop = () => {};
  const g = globalThis as unknown as Record<string, unknown>;
  g.location = location;
  // framer-motion's projection system registers a window resize listener while
  // rendering; no-op listeners are enough for a static render.
  g.window = {
    location,
    matchMedia: () => ({ matches: false }),
    addEventListener: noop,
    removeEventListener: noop,
  };
}

/** JSON-LD structured data for the landing route (schema.org @graph:
 * WebSite + Organization + SoftwareApplication), generated from the real egg
 * catalog so values can never drift from the actual egg JSON. */
function landingJsonLd(): string | null {
  try {
    const cat = JSON.parse(
      readFileSync(resolve(__dir, "..", "src", "data", "catalog.json"), "utf8"),
    );
    const egg = cat.eggs[0];
    const org = {
      "@type": "Organization",
      "@id": "https://potenfyr.in/#organization",
      name: "PotenFYR Studios",
      url: "https://potenfyr.in",
      sameAs: [
        "https://github.com/PotenFYR-Studios",
        "https://modrinth.com/organization/potenfyr",
      ],
    };
    const graph = [
      {
        "@type": "WebSite",
        "@id": `${CANON}/#website`,
        url: `${CANON}/`,
        name: "Database-Eggs Docs",
        description: PAGES[0].desc,
        inLanguage: "en",
        publisher: { "@id": org["@id"] },
      },
      org,
      {
        "@type": "SoftwareApplication",
        name: egg.name,
        applicationCategory: "DeveloperApplication",
        operatingSystem: "Pterodactyl / Pelican / Feather / Wisp / Docker",
        description: egg.description,
        datePublished: egg.exportedAt.slice(0, 10),
        offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
        codeRepository: cat.repo.url,
        downloadUrl: `${cat.repo.rawBase}/${egg.file}`,
        license: `${cat.repo.url}/blob/master/LICENSE`,
        author: { "@id": org["@id"] },
        publisher: { "@id": org["@id"] },
        featureList: [
          `${egg.counts.realEngines} database engines + custom binary target`,
          `${egg.counts.variables} exported startup variables`,
          "Strict version pinning with no silent downgrades",
          "Automatic high-entropy credential generation",
          "Hardware-aware performance auto-tuning",
        ],
      },
    ];
    return JSON.stringify({ "@context": "https://schema.org", "@graph": graph }).replace(
      /<\//g,
      "<\\/",
    );
  } catch {
    return null; // catalog not generated; skip injection rather than fail the build
  }
}

/** Swap every per-page head slot for this page's values. */
function withMeta(html: string, page: PageMeta): string {
  const esc = (s: string) => s.replace(/"/g, "&quot;");
  const canonical = `${CANON}${page.path}`;
  const out = html
    .replace(/<title>.*?<\/title>/s, `<title>${esc(page.title)}</title>`)
    .replace(
      /<meta\s+name="description"\s+content="[^"]*"\s*\/>/,
      `<meta name="description" content="${esc(page.desc)}" />`,
    )
    .replace(
      /<meta\s+property="og:title"\s+content="[^"]*"\s*\/>/,
      `<meta property="og:title" content="${esc(page.title)}" />`,
    )
    .replace(
      /<meta\s+property="og:description"\s+content="[^"]*"\s*\/>/,
      `<meta property="og:description" content="${esc(page.desc)}" />`,
    )
    .replace(
      /<meta\s+property="og:url"\s+content="[^"]*"\s*\/>/,
      `<meta property="og:url" content="${canonical}" />`,
    )
    .replace(
      /<link\s+rel="canonical"\s+href="[^"]*"\s*\/>/,
      `<link rel="canonical" href="${canonical}" />`,
    )
    .replace(
      /<meta\s+name="twitter:title"\s+content="[^"]*"\s*\/>/,
      `<meta name="twitter:title" content="${esc(page.title)}" />`,
    )
    .replace(
      /<meta\s+name="twitter:description"\s+content="[^"]*"\s*\/>/,
      `<meta name="twitter:description" content="${esc(page.desc)}" />`,
    );

  // Fail loudly instead of silently emitting a page with stale head tags.
  if (!out.includes(`<title>${esc(page.title)}</title>`)) {
    throw new Error(`title slot not found for ${page.path}`);
  }
  if (!out.includes(`<link rel="canonical" href="${canonical}" />`)) {
    throw new Error(`canonical slot not found for ${page.path}`);
  }
  if (!out.includes(`<meta property="og:url" content="${canonical}" />`)) {
    throw new Error(`og:url slot not found for ${page.path}`);
  }
  if (!out.includes(OG_IMAGE) || !out.includes(OG_IMAGE_ALT)) {
    throw new Error(`og:image missing for ${page.path}`);
  }
  return out;
}

// ---------------------------------------------------------------- main
try {
  const shell = readFileSync(resolve(distDir, "index.html"), "utf8");
  if (!shell.includes('<div id="root"></div>')) {
    throw new Error("root div placeholder not found in dist/index.html");
  }

  const ld = landingJsonLd();
  let files = 0;

  for (const page of PAGES) {
    stubBrowser(page.path);
    const body = renderToString(
      createElement(StrictMode, null, createElement(App)),
    );
    if (body.length < 500) {
      throw new Error(`rendered body suspiciously small for ${page.path}`);
    }

    let html = withMeta(shell, page).replace(
      '<div id="root"></div>',
      `<div id="root">${body}</div>`,
    );
    if (ld && page.path === "/") {
      html = html.replace(
        "</head>",
        `  <script type="application/ld+json">${ld}</script>\n</head>`,
      );
    }

    const route = page.path === "/" ? "" : page.path.slice(1);
    const targets: string[] = [];
    if (!route) {
      targets.push(resolve(distDir, "index.html"));
    } else {
      mkdirSync(resolve(distDir, route), { recursive: true });
      targets.push(
        resolve(distDir, `${route}index.html`),
        resolve(distDir, `${route.slice(0, -1)}.html`), // slug.html twin
      );
    }
    for (const target of targets) writeFileSync(target, html);

    console.log(
      `[prerender] ${page.path} -> ${targets.map((t) => t.replace(`${distDir}/`, "")).join(", ")} (body ${body.length} chars)`,
    );
    files += targets.length;
  }

  console.log(`[prerender] ${files} HTML files emitted`);
} catch (err) {
  console.error("[prerender] ERROR:", err);
  process.exit(1);
}
