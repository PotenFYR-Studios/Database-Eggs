import { ArrowRight, Database, Github, Server, ShieldCheck } from "lucide-react";
import { Toc, type TocItem } from "../Toc";
import {
  Breadcrumbs,
  data,
  egg,
  Footer,
  Navbar,
  Pagination,
  Sidebar,
} from "../site";

const TOC_ITEMS: TocItem[] = [
  { id: "what-it-is", label: "What it is" },
  { id: "how-it-works", label: "How it works" },
  { id: "security-model", label: "Security model" },
  { id: "open-source", label: "Open source" },
  { id: "license", label: "License" },
];

function About() {
  return (
    <div className="flex min-h-screen flex-col">
      <Navbar />
      <div className="layout">
        <Sidebar />
        <article className="article">
          <Breadcrumbs items={[{ label: "Home", href: "/" }, { label: "About" }]} />
          <div className="eyebrow">Database-Eggs Docs · About</div>
        <h1 className="grad-text-db text-[clamp(1.9em,3.6vw,2.6em)] font-extrabold tracking-tight">
          About Database-Eggs
        </h1>
        <p id="what-it-is" className="mt-4 text-[1.02em] leading-[1.75] text-[#9aa0b4]">
          <strong className="text-[#e8eaf2]">Database-Eggs</strong> is one universal egg that
          runs {egg.counts.realEngines}+ database engines (with strict version contracts,
          zero-leak credential handling and hardware-aware tuning) across every Wings-family
          panel. No bespoke per-engine images, no host root, no stale single-database eggs.
        </p>

        <div className="mt-10 grid gap-6 md:grid-cols-2">
          <div className="doc-card">
            <div className="icon-tile">
              <Server className="h-5 w-5" />
            </div>
            <h2 id="how-it-works" className="text-base font-bold text-white">How it works</h2>
            <p className="mt-1 text-[0.86em] leading-relaxed text-[#9aa0b4]">
              A single egg JSON dispatches on <code className="inline-code">DATABASE_TYPE</code>.
              On first boot the runtime downloads the pinned engine release, SHA-verifies it,
              sizes buffers from the container's RAM/CPU limits, provisions users with
              high-entropy secrets and supervises the daemon with graceful stop handling.
            </p>
          </div>
          <div className="doc-card">
            <div className="icon-tile">
              <ShieldCheck className="h-5 w-5" />
            </div>
            <h2 id="security-model" className="text-base font-bold text-white">Security model</h2>
            <p className="mt-1 text-[0.86em] leading-relaxed text-[#9aa0b4]">
              Runs unprivileged (UID 988). Secrets are generated with{" "}
              <code className="inline-code">openssl</code>/<code className="inline-code">urandom</code>,
              persisted to <code className="inline-code">.env</code> with mode 600, and masked
              in all console output. SCRAM-SHA-256 and per-engine hardening are on by default
              (<code className="inline-code">SECURITY_HARDENING=1</code>).
            </p>
          </div>
          <div className="doc-card">
            <div className="icon-tile">
              <Github className="h-5 w-5" />
            </div>
            <h2 id="open-source" className="text-base font-bold text-white">Open source</h2>
            <p className="mt-1 text-[0.86em] leading-relaxed text-[#9aa0b4]">
              Egg JSON, runtime scripts, tests and CI live in the open. Found a bug or want an
              engine added? Open an issue or a PR; new eggs and engines are always welcome.
              See <code className="inline-code">CONTRIBUTING.md</code> for the egg JSON
              contract.
            </p>
            <a
              href={data.repo.url}
              target="_blank"
              rel="noopener"
              className="mt-auto inline-flex items-center gap-1 pt-2 text-sm text-[#c4b5fd] hover:text-[#f9a8d4]"
            >
              {data.repo.url.replace("https://", "")} <ArrowRight className="h-3.5 w-3.5" />
            </a>
          </div>
          <div className="doc-card">
            <div className="icon-tile">
              <Database className="h-5 w-5" />
            </div>
            <h2 className="text-base font-bold text-white">The PotenFYR nest</h2>
            <p className="mt-1 text-[0.86em] leading-relaxed text-[#9aa0b4]">
              Database-Eggs is part of the PotenFYR Studios egg family. The unified catalog of
              every collection (databases, languages, Minecraft, shells) lives at the nest.
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

        <h2 className="mt-14 border-b border-line pb-2 text-xl font-bold text-white">
          PotenFYR Studios
        </h2>
        <p className="mt-3 text-[0.95em] leading-relaxed text-[#9aa0b4]">
          PotenFYR Studios builds games, plugins, hosting infrastructure and open-source
          developer tools, from Minecraft plugins and Pterodactyl eggs to API security. This
          documentation site is part of the{" "}
          <code className="inline-code">*.docs.potenfyr.in</code> family.
        </p>
        <div className="mt-5 flex flex-wrap gap-3">
          <a href="https://potenfyr.in" target="_blank" rel="noopener" className="btn btn-primary !px-5 !py-2.5 text-xs">
            potenfyr.in
          </a>
          <a href="https://nest.potenfyr.in" target="_blank" rel="noopener" className="btn btn-ghost !px-5 !py-2.5 text-xs">
            Egg Nest
          </a>
          <a href={data.repo.url} target="_blank" rel="noopener" className="btn btn-ghost !px-5 !py-2.5 text-xs">
            GitHub
          </a>
          <a href="https://discord.com/invite/zUaN2FPBec" target="_blank" rel="noopener" className="btn btn-ghost !px-5 !py-2.5 text-xs">
            Discord
          </a>
        </div>

        <h2 id="license" className="mt-14 border-b border-line pb-2 text-xl font-bold text-white">
          License
        </h2>
        <p className="mt-3 text-[0.95em] leading-relaxed text-[#9aa0b4]">
          Database-Eggs is licensed under the{" "}
          <strong className="text-[#e8eaf2]">Apache License 2.0 with the Commons Clause</strong>.
          In plain terms, you can: use it for any purpose, commercial use included; run it on
          any panel or plain Docker; fork it; modify it; redistribute it; self-host it for
          yourself, your community or your customers; and build products or services on top of
          it.
        </p>
        <p className="mt-3 text-[0.95em] leading-relaxed text-[#9aa0b4]">
          What you cannot do: sell the software itself; offer a paid product or service whose
          value derives entirely or substantially from this software's functionality; or use
          PotenFYR names, logos or trademarks. If you redistribute the software, keep the
          license notices intact, including the Commons Clause notice.
        </p>
        <p className="mt-3 text-[0.95em] leading-relaxed text-[#9aa0b4]">
          The authoritative text is the repository's{" "}
          <a href={`${data.repo.url}/blob/master/LICENSE`} target="_blank" rel="noopener">
            LICENSE
          </a>{" "}
          file (Apache-2.0 with the Commons Clause License Condition v1.0); this page is a
          summary, not legal advice.
        </p>

        <Pagination prev={{ href: "/examples/", label: "Examples" }} />
        </article>
        <Toc items={TOC_ITEMS} />
      </div>
      <Footer />
    </div>
  );
}

export default About;
