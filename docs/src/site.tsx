import { useEffect, useMemo, useRef, useState } from "react";
import { clsx } from "clsx";
import { ChevronDown, Search } from "lucide-react";
import { NumberTicker } from "./magicui";
import catalog from "./data/catalog.json";

/* == Catalog types (mirror docs/scripts/build-catalog.ts) ================== */
export interface Engine {
  name: string;
  alias?: string;
}
export interface EngineCategory {
  category: string;
  engines: Engine[];
}
export interface EggVariable {
  name: string;
  description: string;
  env_variable: string;
  default_value: string;
  user_viewable: boolean;
  user_editable: boolean;
  rules: string;
  field_type: string;
}
export interface Egg {
  file: string;
  name: string;
  author: string;
  description: string;
  metaVersion: string;
  updateUrl: string;
  exportedAt: string;
  features: string[];
  dockerImages: { label: string; image: string; tag: string }[];
  startup: string;
  variables: EggVariable[];
  engineCategories: EngineCategory[];
  counts: {
    variables: number;
    dockerImages: number;
    engines: number;
    realEngines: number;
  };
}
export interface Catalog {
  repo: { url: string; rawBase: string; eggFile: string };
  counts: {
    eggs: number;
    dockerImages: number;
    variables: number;
    engines: number;
    realEngines: number;
    panels: number;
  };
  eggs: Egg[];
}

export const data = catalog as unknown as Catalog;
export const egg = data.eggs[0];
export const CANON = "https://database-eggs.docs.potenfyr.in";

/** Deploy base ("/" on a custom domain, "/Database-Eggs/" on github.io
 *  project pages). Set from the docs workflow via VITE_BASE. */
const envBase: unknown = import.meta.env?.BASE_URL;
export const BASE: string =
  typeof envBase === "string" ? envBase
  : typeof process !== "undefined" ? process.env?.VITE_BASE ?? "/"
  : "/";

/** Prefix an in-site path with the deploy base. Idempotent, and a no-op
 *  for anything not site-rooted, so call sites can wrap unconditionally. */
export function withBase(p: string): string {
  if (BASE !== "/" && (p === BASE || p.startsWith(BASE))) return p;
  if (!p.startsWith("/")) return p;
  return `${BASE}${p.slice(1)}`;
}

/* == Route table ============================================================ */
export const ROUTES = [
  { path: "/", label: "Home" },
  { path: "/docs/", label: "Install" },
  { path: "/docs/eggs/", label: "Catalog" },
  { path: "/examples/", label: "Examples" },
  { path: "/about/", label: "About" },
] as const;

/**
 * Normalize a pathname to the canonical trailing-slash form ("/docs/eggs/").
 * Also maps the emitted slug.html twins ("/docs.html" -> "/docs/") so a page
 * hydrates against the same route it was prerendered for.
 */
export function normPath(pathname: string): string {
  let p = pathname;
  if (BASE !== "/") {
    if (p === BASE) p = "/";
    else if (p.startsWith(BASE)) p = p.slice(BASE.length - 1);
  }
  if (p.endsWith(".html")) p = p.slice(0, -".html".length) || "/";
  if (!p.startsWith("/")) p = `/${p}`;
  return p.endsWith("/") || p === "" ? p : `${p}/`;
}

export function currentPath(): string {
  return normPath(window.location.pathname);
}

/* == Docs-shell shared components (W5) ======================================= */
export interface Crumb {
  label: string;
  href?: string;
}

/** Breadcrumbs for nested docs pages (Docs / Catalog pattern). */
export function Breadcrumbs({ items }: { items: Crumb[] }) {
  return (
    <nav className="breadcrumbs" aria-label="Breadcrumb">
      {items.map((c, i) => (
        <span key={i} className="contents">
          {i > 0 && <span aria-hidden>/</span>}
          {c.href ? (
            <a href={withBase(c.href)}>{c.label}</a>
          ) : (
            <span className="crumb-here" aria-current="page">
              {c.label}
            </span>
          )}
        </span>
      ))}
    </nav>
  );
}

const SIDEBAR_GROUPS: { label: string; links: { href: string; text: string }[] }[] = [
  { label: "Get started", links: [{ href: "/docs/", text: "Installation & setup" }] },
  { label: "Reference", links: [{ href: "/docs/eggs/", text: "Egg catalog" }] },
  {
    label: "Resources",
    links: [
      { href: "/examples/", text: "Examples" },
      { href: "/about/", text: "About & license" },
    ],
  },
];

/** Collapsible sidebar with active-state highlighting, shared by all docs routes. */
export function Sidebar() {
  const path = currentPath();
  return (
    <aside className="sidebar">
      {SIDEBAR_GROUPS.map((g) => (
        <SidebarGroup key={g.label} label={g.label}>
          {g.links.map((l) => (
            <a
              key={l.href}
              href={withBase(l.href)}
              className={clsx("sidebar-link", path === l.href && "active")}
              aria-current={path === l.href ? "page" : undefined}
            >
              {l.text}
            </a>
          ))}
        </SidebarGroup>
      ))}
    </aside>
  );
}

function SidebarGroup({ label, children }: { label: string; children: React.ReactNode }) {
  const [open, setOpen] = useState(true);
  return (
    <section>
      <button
        type="button"
        className="sidebar-head"
        aria-expanded={open}
        onClick={() => setOpen((v) => !v)}
      >
        {label}
        <ChevronDown className="h-3 w-3" aria-hidden />
      </button>
      {open && <div className="sidebar-group-body">{children}</div>}
    </section>
  );
}

/** Tab strip for 2+ alternatives (e.g. per-panel import steps). */
export function Tabs({ tabs }: { tabs: { id: string; label: string; content: React.ReactNode }[] }) {
  const [active, setActive] = useState(tabs[0]?.id ?? "");
  return (
    <div>
      <div className="tabs" role="tablist">
        {tabs.map((t) => (
          <button
            key={t.id}
            type="button"
            role="tab"
            className="tab"
            aria-selected={active === t.id}
            onClick={() => setActive(t.id)}
          >
            {t.label}
          </button>
        ))}
      </div>
      {tabs.map((t) => (
        <div key={t.id} role="tabpanel" className="tab-panel" hidden={active !== t.id}>
          {t.content}
        </div>
      ))}
    </div>
  );
}

/* == Navbar (SPEC 5.1) ======================================================= */
export function Navbar() {
  const [open, setOpen] = useState(false);
  const [paletteOpen, setPaletteOpen] = useState(false);
  const path = currentPath();

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setPaletteOpen((v) => !v);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  return (
    <>
      <header className="site-header">
        <a href={withBase("/")} className="brand" aria-label="Database-Eggs home">
          <img src={withBase("/favicon.png")} alt="" />
          <span>
            Database-Eggs<span className="brand-dot">.</span>
          </span>
        </a>
        <nav className="nav-desktop flex items-center gap-1">
          {ROUTES.map((r) => (
            <a
              key={r.path}
              href={withBase(r.path)}
              className={clsx("nav-link", path === r.path && "active")}
            >
              {r.label}
            </a>
          ))}
        </nav>
        <div className="ml-auto flex items-center gap-3">
          <button
            type="button"
            onClick={() => setPaletteOpen(true)}
            className="hidden items-center gap-2 rounded-lg border border-line-light bg-white/[0.03] px-3 py-1.5 text-xs text-[#9aa0b4] transition-colors hover:border-brand-violet/50 sm:flex"
            aria-label="Search docs"
          >
            <Search className="h-3.5 w-3.5" />
            <span>Search</span>
            <kbd>⌘K</kbd>
          </button>
          <a
            href="https://nest.potenfyr.in"
            target="_blank"
            rel="noopener"
            className="header-link hidden md:block"
          >
            Nest
          </a>
          <a
            href={data.repo.url}
            target="_blank"
            rel="noopener"
            className="header-link"
          >
            GitHub
          </a>
          <button
            type="button"
            className="flex h-8 w-8 flex-col items-center justify-center gap-[3px] md:hidden"
            aria-expanded={open}
            aria-label="Toggle menu"
            onClick={() => setOpen((v) => !v)}
          >
            <span className="h-[2px] w-4 bg-[#9aa0b4]" />
            <span className="h-[2px] w-4 bg-[#9aa0b4]" />
            <span className="h-[2px] w-4 bg-[#9aa0b4]" />
          </button>
        </div>
      </header>
      {open && (
        <div className="fixed inset-x-0 top-14 z-40 border-b border-line-light bg-[#0b0d14]/98 px-5 py-4 backdrop-blur-md md:hidden">
          {ROUTES.map((r) => (
            <a
              key={r.path}
              href={withBase(r.path)}
              onClick={() => setOpen(false)}
              className="block rounded-lg px-2 py-2 text-sm text-[#b9bfd4] hover:bg-white/5"
            >
              {r.label}
            </a>
          ))}
        </div>
      )}
      {paletteOpen && <CommandPalette onClose={() => setPaletteOpen(false)} />}
    </>
  );
}

/* == Command palette (SPEC 5.12) ============================================== */
interface PaletteItem {
  title: string;
  hint: string;
  path: string;
  glyph: string;
}

const PALETTE_INDEX: PaletteItem[] = [
  { title: "Home: one egg, every database", hint: "Landing", path: "/", glyph: "→" },
  { title: "Install an egg (Pterodactyl / Pelican / Feather)", hint: "Docs", path: "/docs/", glyph: "→" },
  { title: "Import the egg JSON", hint: "Install", path: "/docs/", glyph: "§" },
  { title: "Startup variables", hint: "Install", path: "/docs/", glyph: "§" },
  { title: "First boot & credentials", hint: "Install", path: "/docs/", glyph: "§" },
  { title: "Updating the egg", hint: "Install", path: "/docs/", glyph: "§" },
  { title: "Egg catalog: engines, images, variables", hint: "Catalog", path: "/docs/eggs/", glyph: "→" },
  { title: "Docker image tags", hint: "Catalog", path: "/docs/eggs/", glyph: "§" },
  { title: "All exported variables", hint: "Catalog", path: "/docs/eggs/", glyph: "§" },
  { title: "Engine matrix", hint: "Catalog", path: "/docs/eggs/", glyph: "§" },
  { title: "Egg JSON excerpt", hint: "Examples", path: "/examples/", glyph: "§" },
  { title: "Docker Compose example", hint: "Examples", path: "/examples/", glyph: "§" },
  { title: "About & PotenFYR Studios", hint: "About", path: "/about/", glyph: "→" },
  { title: "License & permitted use", hint: "About", path: "/about/#license", glyph: "§" },
];

function CommandPalette({ onClose }: { onClose: () => void }) {
  const [q, setQ] = useState("");
  const [sel, setSel] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);

  const results = useMemo(() => {
    const needle = q.trim().toLowerCase();
    const list = needle
      ? PALETTE_INDEX.filter((i) =>
          i.title.toLowerCase().includes(needle) ||
          i.hint.toLowerCase().includes(needle),
        )
      : PALETTE_INDEX;
    return list.slice(0, 14);
  }, [q]);

  useEffect(() => {
    inputRef.current?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
      if (e.key === "ArrowDown") {
        e.preventDefault();
        setSel((s) => Math.min(s + 1, results.length - 1));
      }
      if (e.key === "ArrowUp") {
        e.preventDefault();
        setSel((s) => Math.max(s - 1, 0));
      }
      if (e.key === "Enter" && results[sel]) {
        window.location.href = results[sel].path;
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [results, sel, onClose]);

  return (
    <div className="palette-overlay" onClick={onClose} role="dialog" aria-label="Search">
      <div className="palette-panel" onClick={(e) => e.stopPropagation()}>
        <input
          ref={inputRef}
          className="palette-input"
          placeholder="Search pages and sections…"
          value={q}
          onChange={(e) => {
            setQ(e.target.value);
            setSel(0);
          }}
        />
        <div className="max-h-[320px] overflow-y-auto p-2">
          {results.length === 0 && (
            <div className="px-3 py-6 text-center text-sm text-[#6a7089]">
              No results for “{q}”
            </div>
          )}
          {results.map((r, i) => (
            <div
              key={`${r.title}-${i}`}
              className={clsx("palette-row", i === sel && "sel")}
              onClick={() => (window.location.href = r.path)}
            >
              <span className="font-mono text-[10px] text-[#6a7089]">{r.glyph}</span>
              <span>{r.title}</span>
              <span className="ml-auto font-mono text-[10px] uppercase tracking-widest text-[#6a7089]">
                {r.hint}
              </span>
            </div>
          ))}
        </div>
        <div className="palette-hint">↑↓ navigate · Enter open · Esc close</div>
      </div>
    </div>
  );
}

/* == Footer (SPEC 5.2) ========================================================= */
export function Footer() {
  return (
    <footer className="site-footer">
      <div className="sf-inner">
        <div className="flex flex-col gap-8 md:flex-row md:items-start md:justify-between">
          <div className="max-w-[420px]">
            <div className="brand">
              <img src={withBase("/favicon.png")} alt="" className="h-8 w-8 rounded-full ring-1 ring-white/10" />
              <span className="font-mono font-bold text-white">
                Database-Eggs<span className="brand-dot">.</span>
              </span>
            </div>
            <p className="mt-3 text-[0.8em] text-[#9aa0b4]">
              One egg. Every database. Every version. Every panel.
              Production-ready multi-database eggs by PotenFYR Studios.
            </p>
          </div>
          <div className="sf-link-row md:justify-end md:text-right">
            <a href={data.repo.url} target="_blank" rel="noopener">
              GitHub Org
            </a>
            <a href="https://potenfyr.in" target="_blank" rel="noopener">
              potenfyr.in
            </a>
            <a href="https://discord.com/invite/zUaN2FPBec" target="_blank" rel="noopener">
              Support Discord
            </a>
            <a href="https://nest.potenfyr.in" target="_blank" rel="noopener">
              Egg Nest
            </a>
            <a
              href="https://github.com/PotenFYR-Studios/Database-Eggs/blob/master/LICENSE"
              target="_blank"
              rel="noopener"
            >
              License
            </a>
            <a href={withBase("/")} className="sf-accent">
              Docs
            </a>
          </div>
        </div>
        <div className="sf-legal flex flex-col gap-2 md:flex-row md:items-center md:justify-between">
          <span>© 2026 PotenFYR Studios. Released under Apache-2.0 with Commons Clause.</span>
          <span>Crafted with ♥ for server owners · Made with ❤️ by PotenFYR Studios</span>
        </div>
      </div>
    </footer>
  );
}

/* == Code block with copy button + language tag (SPEC 5.8) ====================== */
export function CodeBlock({
  code,
  lang,
  ariaLabel,
}: {
  code: string;
  lang?: string;
  ariaLabel?: string;
}) {
  const [ok, setOk] = useState(false);
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(code);
      setOk(true);
      setTimeout(() => setOk(false), 1400);
    } catch {
      /* clipboard unavailable */
    }
  };
  return (
    <div className="pre-wrap my-4">
      {lang && <span className="lang-tag">{lang}</span>}
      <pre className="codeblock">
        <code>{code}</code>
      </pre>
      <button type="button" className={clsx("copy-btn", ok && "ok")} onClick={copy}>
        {ok ? "Copied!" : "Copy"}
      </button>
      {ariaLabel && <span className="sr-only">{ariaLabel}</span>}
    </div>
  );
}

/* == Stat tile (SPEC 5.6) ======================================================== */
export function StatTile({
  value,
  label,
  accent,
}: {
  value: number;
  label: string;
  accent: string;
}) {
  return (
    <div className="stat-tile">
      <div className="stat-value grad-text-canonical">
        <NumberTicker value={value} />
      </div>
      <div className="stat-label mt-1" style={{ color: accent }}>
        {label}
      </div>
    </div>
  );
}

/* == Variable table (SPEC 5.7) ==================================================== */
export function VarTable({
  variables,
}: {
  variables: EggVariable[];
}) {
  return (
    <div className="my-4">
      <table className="data-table">
        <thead>
          <tr>
            <th>Variable</th>
            <th>Default</th>
            <th>Editable</th>
            <th>Description</th>
          </tr>
        </thead>
        <tbody>
          {variables.map((v) => (
            <tr key={v.env_variable}>
              <td>
                <code className="inline-code">{v.env_variable}</code>
              </td>
              <td className="whitespace-nowrap font-mono text-xs text-[#9aa0b4]">
                {v.default_value === "" ? "(empty)" : v.default_value}
              </td>
              <td>
                {v.user_editable ? (
                  <span className="status-pill">user</span>
                ) : (
                  <span className="tag">admin</span>
                )}
              </td>
              <td className="min-w-[280px] text-[0.92em] leading-relaxed">
                {v.description.split("\n")[0]}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/* == Prev / next pagination cards (SPEC 6) ========================================= */
export function Pagination({
  prev,
  next,
}: {
  prev?: { href: string; label: string };
  next?: { href: string; label: string };
}) {
  return (
    <div className="mt-12 flex flex-col justify-between gap-4 sm:flex-row">
      {prev ? (
        <a
          href={withBase(prev.href)}
          className="flex-1 rounded-xl border border-line-light bg-white/[0.02] p-4 transition-transform hover:-translate-y-0.5 hover:border-brand-violet/50"
        >
          <div className="eyebrow">← Previous</div>
          <div className="mt-1 text-sm text-[#b9bfd4] hover:text-[#c4b5fd]">{prev.label}</div>
        </a>
      ) : (
        <span className="flex-1" />
      )}
      {next ? (
        <a
          href={withBase(next.href)}
          className="flex-1 rounded-xl border border-line-light bg-white/[0.02] p-4 text-right transition-transform hover:-translate-y-0.5 hover:border-brand-pink/50"
        >
          <div className="eyebrow">Next →</div>
          <div className="mt-1 text-sm text-[#b9bfd4] hover:text-[#f9a8d4]">{next.label}</div>
        </a>
      ) : (
        <span className="flex-1" />
      )}
    </div>
  );
}
