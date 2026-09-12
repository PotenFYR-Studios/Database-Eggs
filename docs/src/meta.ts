/**
 * Single source of truth for the site's pages: canonical paths, titles and
 * per-page descriptions. Consumed by src/App.tsx (routing + document titles)
 * and scripts/prerender.ts (static HTML emission) so the two cannot drift.
 */
export const CANON = "https://database-eggs.docs.potenfyr.in";

export interface PageMeta {
  /** Canonical path with trailing slash ("/" for the landing route). */
  path: string;
  title: string;
  desc: string;
}

export const PAGES: PageMeta[] = [
  {
    path: "/",
    title: "Database-Eggs: One egg. Every database. Every panel.",
    desc: "One production-ready egg for Pterodactyl, Pelican, Feather, Wisp and Docker: 50+ SQL, NoSQL, vector, time-series, search and object-storage engines.",
  },
  {
    path: "/docs/",
    title: "Install an Egg: Database-Eggs Docs",
    desc: "Import the Multi Database egg into Pterodactyl, Pelican or Feather, configure startup variables, connect, and keep the egg updated.",
  },
  {
    path: "/docs/eggs/",
    title: "Egg Catalog: Database-Eggs Docs",
    desc: "The full catalog of Database-Eggs: engines included, Docker image tags and every exported startup variable, generated from the real egg JSON.",
  },
  {
    path: "/examples/",
    title: "Examples: Database-Eggs Docs",
    desc: "A real egg JSON excerpt, a Docker Compose file and panel import commands for the Database-Eggs Multi Database egg.",
  },
  {
    path: "/about/",
    title: "About: Database-Eggs Docs",
    desc: "About Database-Eggs and PotenFYR Studios: one universal egg for every database, every version, every panel.",
  },
];
