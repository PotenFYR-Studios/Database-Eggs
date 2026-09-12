import { useEffect, useRef, useState } from "react";
import { motion } from "motion/react";
import { clsx } from "clsx";

/** Magic UI · Number Ticker: counts up to `value` (rAF, reduced-motion aware). */
export function NumberTicker({
  value,
  className,
}: {
  value: number;
  className?: string;
}) {
  const [display, setDisplay] = useState(0);
  const prev = useRef(0);

  useEffect(() => {
    if (
      typeof document !== "undefined" &&
      (document.hidden ||
        window.matchMedia("(prefers-reduced-motion: reduce)").matches)
    ) {
      prev.current = value;
      setDisplay(value);
      return;
    }
    const from = prev.current;
    const start = performance.now();
    const duration = 900;
    let raf = 0;
    const step = (t: number) => {
      const p = Math.min(1, (t - start) / duration);
      const eased = 1 - Math.pow(1 - p, 3);
      setDisplay(Math.round(from + (value - from) * eased));
      if (p < 1) raf = requestAnimationFrame(step);
      else prev.current = value;
    };
    raf = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf);
  }, [value]);

  return (
    <span className={className} aria-label={String(value)}>
      {display}
    </span>
  );
}

/** Magic UI · Marquee: seamless infinite scroller (pauses on hover). */
export function Marquee({
  children,
  reverse = false,
  pause = true,
  className,
}: {
  children: React.ReactNode;
  reverse?: boolean;
  pause?: boolean;
  className?: string;
}) {
  return (
    <div
      className={clsx(
        "group flex w-full overflow-hidden [--duration:35s] [--gap:3rem] [gap:var(--gap)]",
        className,
      )}
    >
      {[0, 1].map((i) => (
        <div
          key={i}
          aria-hidden={i === 1}
          style={{
            animation: "nestMarqueeScroll var(--duration) linear infinite",
            animationDirection: reverse ? "reverse" : "normal",
          }}
          className={clsx(
            "flex shrink-0 items-center justify-around [gap:var(--gap)] min-w-full",
            pause && "group-hover:[animation-play-state:paused]",
          )}
        >
          {children}
        </div>
      ))}
      <style>{`
        @keyframes nestMarqueeScroll {
          from { transform: translateX(0); }
          to { transform: translateX(calc(-100% - var(--gap))); }
        }
      `}</style>
    </div>
  );
}

/** Magic UI · Border Beam: light beam travelling around a rounded border. */
export function BorderBeam({
  size = 120,
  duration = 7,
  className,
  colorFrom = "#38bdf8",
  colorTo = "#8b5cf6",
}: {
  size?: number;
  duration?: number;
  className?: string;
  colorFrom?: string;
  colorTo?: string;
}) {
  return (
    <div
      className={clsx(
        "pointer-events-none absolute inset-0 rounded-[inherit] border border-transparent [mask-clip:padding-box,border-box] [mask-composite:intersect]",
        className,
      )}
      style={{
        mask: "linear-gradient(#fff 0 0) padding-box, linear-gradient(#fff 0 0)",
      }}
    >
      <motion.div
        className="absolute aspect-square rounded-full"
        style={{
          width: size,
          background: `linear-gradient(to left, transparent, ${colorFrom}, ${colorTo}, transparent)`,
          offsetPath: `rect(0 auto auto 0 round ${size / 2}px)`,
        }}
        animate={{ offsetDistance: ["0%", "100%"] }}
        transition={{ repeat: Infinity, ease: "linear", duration }}
      />
    </div>
  );
}

/** Magic UI · Meteors: streaking comets in the hero (landing only). */
export function Meteors({ number = 14 }: { number?: number }) {
  const meteors = Array.from({ length: number }, (_, i) => ({
    id: i,
    left: (i * 137) % 100,
    delay: ((i * 2.3) % 8).toFixed(1),
    dur: (4.5 + ((i * 1.1) % 4)).toFixed(1),
  }));
  return (
    <div aria-hidden className="pointer-events-none absolute inset-0 overflow-hidden">
      {meteors.map((m) => (
        <span
          key={m.id}
          className="absolute h-0.5 w-0.5 rotate-[215deg] rounded-full bg-brand-sky shadow-[0_0_0_1px_rgba(56,189,248,0.12)] before:content-[''] before:absolute before:top-1/2 before:h-px before:w-20 before:-translate-y-1/2 before:bg-gradient-to-r before:from-[#38bdf8] before:to-transparent"
          style={{
            left: `${m.left}%`,
            top: "-8%",
            animation: `meteor ${m.dur}s linear ${m.delay}s infinite`,
          }}
        />
      ))}
      <style>{`@keyframes meteor { 0% { transform: rotate(215deg) translateX(0); opacity: 1; } 70% { opacity: 1; } 100% { transform: rotate(215deg) translateX(-620px); opacity: 0; } }`}</style>
    </div>
  );
}

/** Magic UI · Glow Orb: ambient atmosphere for the hero only. */
export function GlowOrb({
  className,
  color = "rgba(56, 189, 248, 0.14)",
  size = 420,
}: {
  className?: string;
  color?: string;
  size?: number;
}) {
  return (
    <div
      aria-hidden
      className={clsx(
        "pointer-events-none absolute rounded-full blur-[140px] will-change-transform",
        className,
      )}
      style={{ width: size, height: size, background: color }}
    />
  );
}
