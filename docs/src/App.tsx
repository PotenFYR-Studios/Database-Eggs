import { useEffect } from "react";
import Home from "./pages/Home";
import Docs from "./pages/Docs";
import Eggs from "./pages/Eggs";
import Examples from "./pages/Examples";
import About from "./pages/About";
import { PAGES } from "./meta";
import { normPath } from "./site";

/**
 * Path-based page switch. Every route also exists as a real prerendered
 * dist/<route>/index.html (scripts/prerender.ts), so direct refresh and deep
 * links work, for people and crawlers alike.
 */
function pageFor(path: string) {
  switch (normPath(path)) {
    case "/":
      return <Home />;
    case "/docs/":
      return <Docs />;
    case "/docs/eggs/":
      return <Eggs />;
    case "/examples/":
      return <Examples />;
    case "/about/":
      return <About />;
    default:
      return <Home />;
  }
}

export default function App() {
  useEffect(() => {
    const page = PAGES.find((p) => p.path === normPath(window.location.pathname));
    if (page) document.title = page.title;
  }, []);

  return pageFor(window.location.pathname);
}
