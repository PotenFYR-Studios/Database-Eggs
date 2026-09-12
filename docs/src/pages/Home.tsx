import { ArrowRight, BookOpen, Database, Server, Terminal, Boxes } from "lucide-react";
import { clsx } from "clsx";
import { BorderBeam, GlowOrb, Marquee, Meteors, NumberTicker } from "../magicui";
import { data, egg, Footer, Navbar, StatTile } from "../site";

function Home() {
  const c = data.counts;
  return (
    <div className="flex min-h-screen flex-col">
      <Navbar />
      <main className="flex-1">
        {/* ============ Hero ============ */}
        <section className="relative mx-auto max-w-5xl overflow-visible px-6 pb-16 pt-[72px] text-center">
          <GlowOrb
            className="-top-48 left-[8%]"
            color="rgba(139,92,246,0.16)"
            size={520}
          />
          <GlowOrb
            className="-top-40 right-[6%]"
            color="rgba(56,189,248,0.13)"
            size={460}
          />
          <GlowOrb
            className="left-[35%] top-24"
            color="rgba(236,72,153,0.1)"
            size={400}
          />
          <Meteors number={12} />
          <div className="relative">
            <div className="hero-enter inline-flex items-center gap-2 rounded-full border border-line-light bg-white/[0.03] px-4 py-1.5 font-mono text-[0.75em] text-[#9aa0b4] backdrop-blur">
              <span className="pulse-dot h-2 w-2 rounded-full bg-[#34d399] shadow-[0_0_8px_rgba(16,185,129,0.5)]" />
              PTERODACTYL · PELICAN · FEATHER · WISP · DOCKER
            </div>
            <h1 className="hero-enter-1 mt-6 text-[clamp(2.6em,6vw,4em)] font-extrabold leading-[1.08] tracking-tight grad-text-db">
              One egg. Every database.
            </h1>
            <p className="hero-enter-1 mx-auto mt-4 max-w-[720px] text-[1.04em] leading-[1.75] text-[#9aa0b4]">
              Database-Eggs ships a single production-grade egg that runs{" "}
              <strong className="text-[#e8eaf2]">{c.realEngines}+ engines</strong>: SQL, NoSQL,
              in-memory, vector, time-series, search, graph and object storage, with strict
              version pinning, zero-leak credentials and hardware-aware auto-tuning on every
              Wings-family panel.
            </p>
            <div className="hero-enter-2 mt-8 flex flex-wrap items-center justify-center gap-4">
              <a href="/docs/" className="btn btn-primary">
                Install the egg <ArrowRight className="h-4 w-4" />
              </a>
              <a href="/docs/eggs/" className="btn btn-ghost">
                Browse the catalog
              </a>
            </div>

            <div className="mx-auto mt-12 grid max-w-3xl grid-cols-2 gap-3.5 sm:grid-cols-4">
              <StatTile value={c.realEngines} label="Engines" accent="#38bdf8" />
              <StatTile value={c.variables} label="Exported variables" accent="#c084fc" />
              <StatTile value={c.dockerImages} label="Docker images" accent="#ec4899" />
              <StatTile value={c.panels} label="Panels supported" accent="#818cf8" />
            </div>
          </div>
        </section>

        {/* ============ Engine marquee ============ */}
        <section className="relative mx-auto max-w-7xl px-6 py-10">
          <Marquee>
            {egg.engineCategories.flatMap((cat) =>
              cat.engines.map((e) => (
                <span
                  key={`${cat.category}-${e.name}`}
                  className="flex items-center gap-2 font-mono text-xs uppercase tracking-widest text-[#6a7089]"
                >
                  <span className="text-brand-sky">◆</span> {e.name}
                  {e.alias && <span className="text-[#4a5069]">/{e.alias}</span>}
                </span>
              )),
            )}
          </Marquee>
        </section>

        {/* ============ The egg ============ */}
        <section className="mx-auto max-w-7xl px-6 py-14">
          <div className="eyebrow">The Egg</div>
          <h2 className="mt-2 text-2xl font-bold text-white">
            A single egg definition carries the whole fleet
          </h2>
          <div className="mt-8 grid gap-6 lg:grid-cols-3">
            <div className="doc-card relative lg:col-span-2">
              <BorderBeam size={90} duration={8} />
              <div className="flex items-start justify-between gap-4">
                <div className="icon-tile">
                  <Database className="h-5 w-5" />
                </div>
                <span className="status-pill">{egg.metaVersion}</span>
              </div>
              <h3 className="mt-3 text-lg font-semibold text-white">{egg.name}</h3>
              <p className="mt-1 text-[0.86em] leading-relaxed text-[#9aa0b4]">
                {egg.description}
              </p>
              <div className="mt-4 flex flex-wrap gap-2">
                {egg.dockerImages.map((img) => (
                  <span key={img.image} className="tag-sky tag font-mono">
                    {img.image}
                  </span>
                ))}
                {egg.features.map((f) => (
                  <span key={f} className="tag font-mono">
                    {f}
                  </span>
                ))}
              </div>
              <div className="mt-5 flex flex-wrap items-center gap-4 font-mono text-[11px] uppercase tracking-widest text-[#6a7089]">
                <span>
                  <NumberTicker value={egg.counts.variables} className="text-[#c084fc]" />{" "}
                  variables
                </span>
                <span>
                  <NumberTicker value={egg.counts.engines} className="text-[#38bdf8]" /> engine
                  targets
                </span>
                <span>exported {egg.exportedAt.slice(0, 10)}</span>
              </div>
            </div>
            <div className="flex flex-col gap-6">
              <div className="doc-card">
                <div className="icon-tile">
                  <Server className="h-5 w-5" />
                </div>
                <h3 className="text-[0.98em] font-semibold text-white">Every panel</h3>
                <p className="text-[0.83em] leading-relaxed text-[#9aa0b4]">
                  Auto-detects Pterodactyl, Pelican, Feather, Wisp and plain Docker. One JSON
                  file, one image: import it anywhere a Wings-family daemon runs.
                </p>
                <a
                  href="/docs/"
                  className="mt-auto inline-flex items-center gap-1 pt-2 text-sm text-[#c4b5fd] hover:text-[#f9a8d4]"
                >
                  Install guide <ArrowRight className="h-3.5 w-3.5" />
                </a>
              </div>
              <div className="doc-card">
                <div className="icon-tile">
                  <Boxes className="h-5 w-5" />
                </div>
                <h3 className="text-[0.98em] font-semibold text-white">Full catalog</h3>
                <p className="text-[0.83em] leading-relaxed text-[#9aa0b4]">
                  This site is generated from the real egg JSON. The unified PotenFYR nest
                  mirrors every egg collection in one place.
                </p>
                <a
                  href="https://nest.potenfyr.in"
                  target="_blank"
                  rel="noopener"
                  className="mt-auto inline-flex items-center gap-1 pt-2 text-sm text-[#c4b5fd] hover:text-[#f9a8d4]"
                >
                  nest.potenfyr.in <ArrowRight className="h-3.5 w-3.5" />
                </a>
              </div>
            </div>
          </div>
        </section>

        {/* ============ Engine categories ============ */}
        <section className="mx-auto max-w-7xl px-6 py-14">
          <div className="eyebrow">Coverage</div>
          <h2 className="mt-2 text-2xl font-bold text-white">
            {egg.engineCategories.length} engine categories, one <code className="inline-code">DATABASE_TYPE</code>
          </h2>
          <p className="mt-2 max-w-[720px] text-[0.92em] text-[#9aa0b4]">
            Set one startup variable and the runtime downloads, verifies and tunes the engine on
            first boot. Everything below is parsed live from the egg's{" "}
            <code className="inline-code">DATABASE_TYPE</code> description.
          </p>
          <div className="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {egg.engineCategories.map((cat) => (
              <div key={cat.category} className="doc-card">
                <div className="icon-tile">
                  <Terminal className="h-5 w-5" />
                </div>
                <h3 className="text-[0.98em] font-semibold text-white">{cat.category}</h3>
                <div className="mt-2 flex flex-wrap gap-1.5">
                  {cat.engines.map((e) => (
                    <span key={e.name} className="chip">
                      {e.name}
                      {e.alias ? ` (${e.alias})` : ""}
                    </span>
                  ))}
                </div>
              </div>
            ))}
            <div className="doc-card">
              <div className="icon-tile">
                <BookOpen className="h-5 w-5" />
              </div>
              <h3 className="text-[0.98em] font-semibold text-white">Version pinning</h3>
              <p className="text-[0.83em] leading-relaxed text-[#9aa0b4]">
                <code className="inline-code">latest</code>, a major (<code className="inline-code">18</code>),
                a series (<code className="inline-code">11.4</code>), an exact patch (
                <code className="inline-code">8.0.45</code>) or a direct URL, verified against
                the running binary, never silently downgraded.
              </p>
              <a
                href="/docs/eggs/"
                className={clsx(
                  "mt-auto inline-flex items-center gap-1 pt-2 text-sm text-[#c4b5fd] hover:text-[#f9a8d4]",
                )}
              >
                See all variables <ArrowRight className="h-3.5 w-3.5" />
              </a>
            </div>
          </div>
        </section>

        {/* ============ CTA ============ */}
        <section className="mx-auto max-w-3xl px-6 py-20 text-center">
          <h2 className="grad-text-db text-3xl font-extrabold tracking-tight">
            Ready to deploy in five minutes?
          </h2>
          <p className="mt-3 text-[0.95em] text-[#9aa0b4]">
            Download the JSON, import it into your panel, set two variables, start.
          </p>
          <div className="mt-7 flex flex-wrap items-center justify-center gap-4">
            <a href="/docs/" className="btn btn-primary">
              Get started <ArrowRight className="h-4 w-4" />
            </a>
            <a href={data.repo.url} target="_blank" rel="noopener" className="btn btn-ghost">
              View source
            </a>
          </div>
        </section>
      </main>
      <Footer />
    </div>
  );
}

export default Home;
