import { Toc, type TocItem } from "../Toc";
import {
  Breadcrumbs,
  CodeBlock,
  data,
  egg,
  Footer,
  Navbar,
  Pagination,
  Sidebar,
} from "../site";

/** Build the real egg JSON excerpt from the catalog (no hand-written JSON). */
function eggExcerpt(): string {
  const excerpt = {
    _comment:
      "Excerpt of egg-database-multi.json - see the repo for the full exported egg.",
    meta: { version: egg.metaVersion, update_url: egg.updateUrl },
    exported_at: egg.exportedAt,
    name: egg.name,
    docker_images: Object.fromEntries(
      egg.dockerImages.map((img) => [img.label, img.image]),
    ),
    variables: egg.variables.slice(0, 2).map((v) => ({
      name: v.name,
      description: v.description,
      env_variable: v.env_variable,
      default_value: v.default_value,
      user_viewable: v.user_viewable,
      user_editable: v.user_editable,
      rules: v.rules,
      field_type: v.field_type,
    })),
  };
  return JSON.stringify(excerpt, null, 2);
}

const TOC_ITEMS: TocItem[] = [
  { id: "egg-json", label: "Egg JSON excerpt" },
  { id: "compose", label: "Docker Compose" },
  { id: "panel-import", label: "Panel import" },
];

const COMPOSE_EXAMPLE = `services:
  database:
    image: ${egg.dockerImages[0].image}
    container_name: my-database
    restart: unless-stopped
    ports:
      - "5432:5432"            # primary database port
    environment:
      DATABASE_TYPE: postgresql
      DB_VERSION: "18"
      DB_NAME: appdb
      DB_USERNAMES: alice,bob
      DB_PASSWORDS: ""          # empty slot = auto-generate
      DB_ROOT_PASSWORD: ""      # empty = auto-generate
      AUTO_GENERATE_CREDENTIALS: "1"
      SAVE_TO_ENV: "1"
      PERFORMANCE_TUNING: "1"
      SECURITY_HARDENING: "1"
    volumes:
      - ./data:/home/container/data
    # Credentials land in ./data/../.env inside the container;
    # read them with:  docker exec my-database cat /home/container/.env
    stop_grace_period: 30s
    # The image ships tini as PID 1 with graceful signal handling;
    # no custom entrypoint needed for standalone Docker.`;

function Examples() {
  return (
    <div className="flex min-h-screen flex-col">
      <Navbar />
      <div className="layout">
        <Sidebar />
        <article className="article">
          <Breadcrumbs items={[{ label: "Home", href: "/" }, { label: "Examples" }]} />
          <div className="eyebrow">Database-Eggs Docs · Examples</div>
        <h1 className="grad-text-db text-[clamp(1.9em,3.6vw,2.6em)] font-extrabold tracking-tight">
          Examples
        </h1>
        <p className="mt-2 text-[1.02em] text-[#9aa0b4]">
          Real, copy-pasteable artifacts for the <strong>{egg.name}</strong> egg, generated
          from the actual egg JSON in this repository.
        </p>

        {/* ---- Egg JSON excerpt ---- */}
        <h2 id="egg-json" className="mt-12 border-b border-line pb-2 text-xl font-bold text-white">
          1 · Egg JSON excerpt
        </h2>
        <p className="mt-3 text-[0.95em] text-[#9aa0b4]">
          The head of the exported egg definition ({egg.file}, PTDL {egg.metaVersion}): meta,
          the universal Docker image, and the first exported variables. Every variable follows
          this shape: <code className="inline-code">env_variable</code> is what the runtime
          reads, <code className="inline-code">rules</code> is the panel-side validation.
        </p>
        <CodeBlock lang="json" code={eggExcerpt()} />
        <p className="text-[0.92em] text-[#9aa0b4]">
          Grab the complete file ({egg.counts.variables} variables,{" "}
          {egg.counts.engines} engine targets):
        </p>
        <CodeBlock
          lang="bash"
          code={`curl -fsSL ${data.repo.rawBase}/${egg.file} -o egg-database-multi.json`}
        />

        {/* ---- Docker Compose ---- */}
        <h2 id="compose" className="mt-12 border-b border-line pb-2 text-xl font-bold text-white">
          2 · Docker Compose
        </h2>
        <p className="mt-3 text-[0.95em] text-[#9aa0b4]">
          Standalone Docker needs no panel: the same image and the same exported variables. The
          compose below boots PostgreSQL 18 with two auto-provisioned users.
        </p>
        <CodeBlock lang="yaml" code={COMPOSE_EXAMPLE} />
        <p className="mt-4 text-[0.92em] text-[#9aa0b4]">
          Start it and read the generated credentials:
        </p>
        <CodeBlock
          lang="bash"
          code={`docker compose up -d
docker exec my-database cat /home/container/.env   # DB_PASSWORD, DB_ROOT_PASSWORD, ...`}
        />

        {/* ---- Panel import ---- */}
        <h2 id="panel-import" className="mt-12 border-b border-line pb-2 text-xl font-bold text-white">
          3 · Panel import
        </h2>
        <p className="mt-3 text-[0.95em] text-[#9aa0b4]">
          Pterodactyl / Jexactyl: <strong>Admin → Nests → Import Egg</strong>. Pelican:{" "}
          <strong>Admin → Eggs → Import</strong>. Both accept the same PTDL_v2 file. Or let the
          panel fetch it by URL during import:
        </p>
        <CodeBlock
          lang="text"
          code={`${data.repo.rawBase}/${egg.file}`}
        />
        <p className="mt-4 text-[0.92em] text-[#9aa0b4]">
          Full step-by-step with variable explanations: the{" "}
          <a href="/docs/" className="text-[#c4b5fd] hover:text-[#f9a8d4]">
            install guide
          </a>
          .
        </p>

        <Pagination
          prev={{ href: "/docs/eggs/", label: "Egg catalog" }}
          next={{ href: "/about/", label: "About" }}
        />
        </article>
        <Toc items={TOC_ITEMS} />
      </div>
      <Footer />
    </div>
  );
}

export default Examples;
