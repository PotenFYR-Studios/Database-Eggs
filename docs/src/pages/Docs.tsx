import {
  Breadcrumbs,
  CodeBlock,
  data,
  egg,
  Footer,
  Navbar,
  Pagination,
  Sidebar,
  Tabs,
  VarTable,
} from "../site";
import { Toc } from "../Toc";

const RAW_EGG_URL = `${data.repo.rawBase}/egg-database-multi.json`;

const TOC_ITEMS = [
  { id: "requirements", label: "Requirements" },
  { id: "import", label: "Import the egg" },
  { id: "server", label: "Create a server & set variables" },
  { id: "first-boot", label: "First boot & credentials" },
  { id: "updating", label: "Updating the egg" },
  { id: "troubleshooting", label: "Troubleshooting" },
];

function Docs() {
  return (
    <div className="flex min-h-screen flex-col">
      <Navbar />
      <div className="layout">
        <Sidebar />
        <article className="article">
          <Breadcrumbs items={[{ label: "Home", href: "/" }, { label: "Install an egg" }]} />
          <div className="eyebrow">Database-Eggs Docs · Egg {egg.metaVersion}</div>
          <h1 className="grad-text-db">Install an egg</h1>
          <p className="text-[1.02em] text-[#9aa0b4]">
            The <strong>Multi Database</strong> egg deploys any of{" "}
            {egg.counts.realEngines}+ engines from one JSON definition and one Docker image.
            Works on Pterodactyl, Jexactyl, Pelican, Feather, Wisp and plain Docker.
          </p>

          {/* ---- 1. Requirements ---- */}
          <h2 id="requirements">Requirements</h2>
          <ul>
            <li>
              Any panel running a Wings-family daemon (Pterodactyl 1.x, Pelican, Feather,
              Wisp) or a plain Docker host.
            </li>
            <li>
              The container image <code className="inline-code">{egg.dockerImages[0].image}</code>{" "}
              (pulled automatically on first start).
            </li>
            <li>One allocated port for the database (the primary allocation).</li>
            <li>
              Outbound internet on first boot: engines outside the base image are downloaded,
              SHA-verified and cached under <code className="inline-code">bin/</code>.
            </li>
          </ul>

          {/* ---- 2. Import the egg ---- */}
          <h2 id="import">Import the egg</h2>
          <p>
            Download the exported egg JSON ({""}
            <code className="inline-code">{egg.file}</code>) from the repo (exported{" "}
            {egg.exportedAt.slice(0, 10)}):
          </p>
          <CodeBlock
            lang="bash"
            code={`curl -fsSL ${RAW_EGG_URL} -o egg-database-multi.json`}
          />
          <Tabs
            tabs={[
              {
                id: "pterodactyl",
                label: "Pterodactyl / Jexactyl",
                content: (
                  <ul>
                    <li>
                      <strong>Admin → Nests</strong>: create (or pick) a nest, then{" "}
                      <strong>Import Egg</strong> and upload{" "}
                      <code className="inline-code">egg-database-multi.json</code>.
                    </li>
                    <li>
                      Keep <em>Associated Docker image</em> ={" "}
                      <code className="inline-code">ghcr.io/potenfyr-studios/database-eggs</code>.
                    </li>
                  </ul>
                ),
              },
              {
                id: "pelican",
                label: "Pelican",
                content: (
                  <ul>
                    <li>
                      <strong>Admin → Eggs → Import</strong>: drop the JSON in. Pelican reads the
                      same PTDL_v2 format ({egg.metaVersion}).
                    </li>
                  </ul>
                ),
              },
              {
                id: "feather",
                label: "Feather / Wisp / other",
                content: (
                  <ul>
                    <li>
                      Import the same JSON; the runtime auto-detects the panel via daemon
                      environment fingerprints and adapts stop signals and stdin watching.
                    </li>
                  </ul>
                ),
              },
            ]}
          />

          {/* ---- 3. Create a server ---- */}
          <h2 id="server">Create a server &amp; set variables</h2>
          <p>
            Create a server on the egg and allocate its primary port. The two variables that
            matter first:
          </p>
          <CodeBlock
            lang="startup variables"
            code={`DATABASE_TYPE=postgresql    # any of the ${egg.counts.realEngines} engines (see catalog)
DB_VERSION=18              # latest | 18 | 11.4 | 8.0.45 | https://...`}
          />
          <p>
            Everything else can stay at its default. The core credential variables (all
            exported by the egg):
          </p>
          <VarTable
            variables={egg.variables.filter((v) =>
              [
                "DATABASE_TYPE",
                "DB_VERSION",
                "DB_NAME",
                "DB_USERNAMES",
                "DB_PASSWORDS",
                "DB_ROOT_PASSWORD",
                "STRICT_VERSION",
              ].includes(v.env_variable),
            )}
          />
          <p>
            The full list of all {egg.counts.variables} exported variables (version switching,
            git sync, host tuning, console theming) is in the{" "}
            <a href="/docs/eggs/">egg catalog</a>.
          </p>

          {/* ---- 4. First boot ---- */}
          <h2 id="first-boot">First boot &amp; credentials</h2>
          <p>
            On start the runtime resolves your <code className="inline-code">DB_VERSION</code>,
            verifies the binary, applies hardware-aware tuning, provisions users, and prints a
            connection card. With <code className="inline-code">AUTO_GENERATE_CREDENTIALS=1</code>{" "}
            (default), empty or <code className="inline-code">auto</code> password fields get
            cryptographically random secrets.
          </p>
          <p>
            Credentials are persisted to <code className="inline-code">/home/container/.env</code>{" "}
            (mode <code className="inline-code">600</code>) when{" "}
            <code className="inline-code">SAVE_TO_ENV=1</code>:
          </p>
          <CodeBlock
            lang=".env file"
            code={`DB_CONNECTION=postgresql
DB_HOST=127.0.0.1
DB_PORT=5432
DB_DATABASE=database
DB_USERNAME=dbuser
DB_PASSWORD="<auto-generated>"
DB_ROOT_PASSWORD="<auto-generated>"
DB_VERSION=18`}
          />
          <p>
            Inside the server console, <code className="inline-code">db-cli</code> connects with
            the stored credentials for SQL engines. Set{" "}
            <code className="inline-code">DB_USERNAMES=alice,bob</code> to provision multiple
            users, each with a private <code className="inline-code">&lt;user&gt;_db</code>{" "}
            database plus access to the shared one.
          </p>

          {/* ---- 5. Updating ---- */}
          <h2 id="updating">Updating the egg</h2>
          <ul>
            <li>
              <strong>In-place (self-update)</strong>: the egg ships with{" "}
              <code className="inline-code">AUTO_UPDATE_EGG=1</code> and checks{" "}
              <code className="inline-code">EGG_UPDATE_URL</code> ({egg.updateUrl}) on startup,
              refreshing the launcher when upstream changed.
            </li>
            <li>
              <strong>Panel-side</strong>: re-import the updated JSON over the existing egg
              (Pterodactyl: Nests → egg → <em>Update</em>; Pelican: Eggs → Import). Existing
              servers pick up new variables on next start; a panel <em>Reinstall</em> refreshes
              the runtime scripts without touching <code className="inline-code">data/</code>.
            </li>
            <li>
              Version switching (<code className="inline-code">DB_VERSION</code>) never deletes
              data: each engine/major keeps its own{" "}
              <code className="inline-code">data/&lt;engine&gt;/&lt;series&gt;</code> instance,
              and <code className="inline-code">ARCHIVE_ON_SWITCH=1</code> snapshots the old
              datadir into <code className="inline-code">./archive/</code> first.
            </li>
          </ul>

          {/* ---- 6. Troubleshooting ---- */}
          <h2 id="troubleshooting">Troubleshooting</h2>
          <ul>
            <li>
              <code className="inline-code">logs/startup_error.log</code>: crash reports and
              environment snapshots.
            </li>
            <li>
              <code className="inline-code">logs/installer.log</code>: download traces and HTTP
              probe responses when a version fails to resolve.
            </li>
            <li>
              <code className="inline-code">logs/&lt;engine&gt;.log</code>: engine daemon
              output (e.g. <code className="inline-code">mongod.log</code>,{" "}
              <code className="inline-code">mariadb.log</code>).
            </li>
          </ul>
          <p>
            Strict version check failed? Check <code className="inline-code">logs/installer.log</code>{" "}
            for the upstream probe result, or set{" "}
            <code className="inline-code">STRICT_VERSION=0</code> to warn-and-proceed.
          </p>

          <Pagination
            next={{ href: "/docs/eggs/", label: "Egg catalog" }}
          />
        </article>
        <Toc items={TOC_ITEMS} />
      </div>
      <Footer />
    </div>
  );
}

export default Docs;
