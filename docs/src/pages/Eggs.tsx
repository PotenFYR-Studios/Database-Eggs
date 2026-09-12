import { Database } from "lucide-react";
import {
  Breadcrumbs,
  CodeBlock,
  data,
  egg,
  Footer,
  Navbar,
  Pagination,
  Sidebar,
  VarTable,
  withBase,
} from "../site";
import { Toc, type TocItem } from "../Toc";

const TOC_ITEMS: TocItem[] = [
  { id: "multi-database", label: "Multi Database" },
  { id: "docker-images", label: "Docker images" },
  { id: "engines", label: "Databases included" },
  { id: "variables", label: "All exported variables" },
];

function Eggs() {
  return (
    <div className="flex min-h-screen flex-col">
      <Navbar />
      <div className="layout">
        <Sidebar />
        <article className="article">
          <Breadcrumbs
            items={[
              { label: "Home", href: "/" },
              { label: "Docs", href: "/docs/" },
              { label: "Egg catalog" },
            ]}
          />
          <div className="eyebrow">Database-Eggs Docs · Catalog</div>
          <h1 className="grad-text-db">Egg catalog</h1>
          <p className="text-[1.02em] text-[#9aa0b4]">
            Every egg published in this repository, generated directly from the exported egg
            JSON: engines, Docker images and all {data.counts.variables} startup variables. The
            unified mirror lives at{" "}
            <a href="https://nest.potenfyr.in" target="_blank" rel="noopener">
              nest.potenfyr.in
            </a>
            .
          </p>

          {/* ---- Egg entry ---- */}
          <h2 id="multi-database">{egg.name}</h2>
          <div className="doc-card mt-4">
            <div className="flex items-start justify-between gap-4">
              <div className="icon-tile">
                <Database className="h-5 w-5" />
              </div>
              <div className="flex flex-wrap items-center gap-2">
                <span className="status-pill">{egg.metaVersion}</span>
                <span className="tag font-mono">{egg.file}</span>
              </div>
            </div>
            <p className="mt-3 text-[0.9em] leading-relaxed text-[#9aa0b4]">{egg.description}</p>
            <dl className="mt-4 grid gap-x-8 gap-y-2 font-mono text-xs text-[#9aa0b4] sm:grid-cols-2">
              <div>
                <dt className="inline text-[#6a7089]">author: </dt>
                <dd className="inline">{egg.author}</dd>
              </div>
              <div>
                <dt className="inline text-[#6a7089]">exported: </dt>
                <dd className="inline">{egg.exportedAt.slice(0, 10)}</dd>
              </div>
              <div>
                <dt className="inline text-[#6a7089]">variables: </dt>
                <dd className="inline">{egg.counts.variables}</dd>
              </div>
              <div>
                <dt className="inline text-[#6a7089]">features: </dt>
                <dd className="inline">{egg.features.join(", ") || "(none)"}</dd>
              </div>
            </dl>
            <div className="mt-4 flex flex-wrap gap-2">
              <a href={withBase("/examples/")} className="btn btn-ghost !px-4 !py-2 text-xs">
                JSON &amp; compose examples
              </a>
              <a
                href={`${data.repo.rawBase}/${egg.file}`}
                className="btn btn-ghost !px-4 !py-2 text-xs"
                target="_blank"
                rel="noopener"
              >
                Raw egg JSON
              </a>
            </div>
          </div>

          {/* ---- Docker images ---- */}
          <h2 id="docker-images">Docker image tags</h2>
          <p>
            The egg uses a single universal image; engines not baked into the base image are
            provisioned on demand into <code className="inline-code">bin/</code> and cached
            across boots.
          </p>
          <table className="data-table my-4">
            <thead>
              <tr>
                <th>Image option</th>
                <th>Reference</th>
                <th>Tag</th>
              </tr>
            </thead>
            <tbody>
              {egg.dockerImages.map((img) => (
                <tr key={img.image}>
                  <td className="text-[#e8eaf2]">{img.label}</td>
                  <td>
                    <code className="inline-code">{img.image}</code>
                  </td>
                  <td>
                    <span className="tag-sky tag font-mono">{img.tag}</span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>

          {/* ---- Engines ---- */}
          <h2 id="engines">Databases included</h2>
          <p>
            {egg.counts.engines} dispatch targets ({egg.counts.realEngines} engines plus the{" "}
            <code className="inline-code">custom</code> bring-your-own binary target), selected
            via <code className="inline-code">DATABASE_TYPE</code>. Aliases are shown in
            parentheses.
          </p>
          <div className="mt-4 flex flex-col gap-3">
            {egg.engineCategories.map((cat) => (
              <div key={cat.category} className="doc-card">
                <h3 className="text-[0.95em] font-semibold text-white">{cat.category}</h3>
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
          </div>

          {/* ---- Variables ---- */}
          <h2 id="variables">All exported variables</h2>
          <p>
            Every variable the egg exports to the panel. <span className="status-pill">user</span>{" "}
            = viewable &amp; editable by server owners; <span className="tag">admin</span> = root
            admin only.
          </p>
          <VarTable variables={egg.variables} />

          {/* ---- Startup command ---- */}
          <h3>Startup command</h3>
          <p>
            For reference, the exact startup line the egg runs (it prefers the on-disk
            entrypoint and only fetches the remote bootstrap as a fallback):
          </p>
          <CodeBlock lang="startup" code={egg.startup} />

          <Pagination
            prev={{ href: "/docs/", label: "Install an egg" }}
            next={{ href: "/examples/", label: "Examples" }}
          />
        </article>
        <Toc items={TOC_ITEMS} />
      </div>
      <Footer />
    </div>
  );
}

export default Eggs;
