import { useEffect, useState } from "react";
import { clsx } from "clsx";

export interface TocItem {
  id: string;
  label: string;
}

/** Right-rail TOC with IntersectionObserver active state (SPEC 5.9 / 6). */
export function Toc({ items }: { items: TocItem[] }) {
  const [active, setActive] = useState(items[0]?.id ?? "");

  useEffect(() => {
    const headings = items
      .map((i) => document.getElementById(i.id))
      .filter((el): el is HTMLElement => el !== null);
    if (headings.length === 0) return;

    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) setActive(entry.target.id);
        }
      },
      { rootMargin: "-80px 0px -65% 0px" },
    );
    headings.forEach((h) => observer.observe(h));
    return () => observer.disconnect();
  }, [items]);

  return (
    <nav className="toc" aria-label="On this page">
      <div className="toc-title grad-text-db">
        On this page
        <span className="ml-2 rounded-full border border-line px-1.5 py-px text-[9px] text-[#6a7089]">
          {items.length}
        </span>
      </div>
      {items.map((i) => (
        <a
          key={i.id}
          href={`#${i.id}`}
          className={clsx("toc-item", active === i.id && "active")}
        >
          {i.label}
        </a>
      ))}
    </nav>
  );
}
