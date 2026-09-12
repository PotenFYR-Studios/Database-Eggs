import { StrictMode } from "react";
import { createRoot, hydrateRoot } from "react-dom/client";
import "./index.css";
import App from "./App";

// Pages prerendered by scripts/prerender.ts carry full server HTML in #root,
// hydrate in place so nothing re-renders or flashes. The bare Vite dev server
// serves an empty #root, so fall back to a client-only render there.
const root = document.getElementById("root")!;
const tree = (
  <StrictMode>
    <App />
  </StrictMode>
);

if (root.hasChildNodes()) {
  hydrateRoot(root, tree);
} else {
  createRoot(root).render(tree);
}
