import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// Per-route HTML emission (prerendered body + title/description/canonical/OG/
// Twitter meta + landing JSON-LD) lives in scripts/prerender.ts, which runs
// after `vite build` as part of `bun run build`.

export default defineConfig({
  root: resolve(dirname(fileURLToPath(import.meta.url))),
  base: process.env.VITE_BASE ?? "/",
  plugins: [react(), tailwindcss()],
  build: {
    outDir: "dist",
    emptyOutDir: true,
  },
});
