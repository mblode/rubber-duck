import type { ComponentProps, ReactNode } from "react";
import { cn } from "@/lib/utils";

const Section = ({
  className,
  children,
  ...props
}: ComponentProps<"section">) => (
  <section className={cn("scroll-mt-20 py-20 sm:py-32", className)} {...props}>
    {children}
  </section>
);

const Container = ({
  className,
  children,
  ...props
}: ComponentProps<"div">) => (
  <div
    className={cn("mx-auto w-full max-w-7xl px-5 sm:px-8", className)}
    {...props}
  >
    {children}
  </div>
);

interface SectionHeadingProps {
  align?: "start" | "center";
  children: ReactNode;
  className?: string;
  eyebrow?: string;
  lede?: ReactNode;
}

const SectionHeading = ({
  align = "start",
  children,
  className,
  eyebrow,
  lede,
}: SectionHeadingProps) => (
  <div className={cn(align === "center" && "text-center", className)}>
    {eyebrow ? (
      <p className="mb-4 font-mono text-duck text-sm">{eyebrow}</p>
    ) : null}
    <h2
      className={cn(
        "max-w-[22ch] text-balance font-medium text-4xl text-ink tracking-[-0.04em] sm:text-6xl sm:leading-[1.02]",
        align === "center" && "mx-auto"
      )}
    >
      {children}
    </h2>
    {lede ? (
      <p
        className={cn(
          "mt-6 max-w-[54ch] text-pretty text-ink-muted text-lg",
          align === "center" && "mx-auto"
        )}
      >
        {lede}
      </p>
    ) : null}
  </div>
);

export { Container, Section, SectionHeading };
