/**
 * The trail back to the hub, rendered at the top of a zone's ROOT page.
 *
 * Copied from blode-co's `components/zone-breadcrumb.tsx` (these are separate
 * Next apps and cannot import from each other), so keep it dependency-free: no
 * `next/link`, no icon package, no local `cn()`. The one deviation from the
 * reference is the colour tokens: this page paints on `--color-canvas` with the
 * Apple grey `ink` scale, and `text-muted-foreground` is tuned against
 * `--background` instead, so it would read wrong here.
 *
 * Three constraints, all of them load-bearing:
 *
 * 1. **Absolute `https://blode.co` hrefs.** A bare `href="/"` is not
 *    `basePath`-prefixed, so in a zone it resolves against the child's own
 *    origin and breaks on preview deployments.
 * 2. **Plain `<a>`, never `next/link`.** `next/link` would prefetch an RSC
 *    payload for a route this app does not own. These are also same-origin
 *    (a zone is blode.co behind a rewrite), so: same tab, and no
 *    `rel="noopener noreferrer"`, which only means something cross-origin.
 * 3. **The desktop trail matches `BreadcrumbList`.** The narrow header omits
 *    only the root crumb so the current product never wraps; Projects and the
 *    current page remain visible navigation.
 *
 * Root page only. Inner pages have their own navigation and a second trail
 * would just be noise.
 */

const HOME = "https://blode.co";
const PROJECTS = `${HOME}/projects`;

const linkClassName =
  "underline decoration-current/25 underline-offset-2 hover:text-ink hover:decoration-current focus-visible:outline-2 focus-visible:outline-ring focus-visible:outline-offset-2";

const Separator = () => (
  // Decorative: the <ol> already conveys the structure to assistive tech.
  <span aria-hidden className="select-none opacity-40">
    ›
  </span>
);

export const ZoneBreadcrumb = ({ product }: { product: string }) => (
  <nav aria-label="Breadcrumb" className="text-[13px] text-ink-subtle">
    <ol className="flex items-center gap-1.5 sm:hidden">
      <li className="flex items-center gap-1.5">
        <a className={linkClassName} href={PROJECTS}>
          Projects
        </a>
        <Separator />
      </li>
      <li aria-current="page" className="text-ink">
        {product}
      </li>
    </ol>
    <ol className="hidden items-center gap-1.5 sm:flex">
      <li className="flex items-center gap-1.5">
        {/*
          `rel="author"` marks this as the identity edge, matching the footer
          credit. Only this crumb carries it; /projects is a collection.
        */}
        <a className={linkClassName} href={HOME} rel="author">
          Matthew Blode
        </a>
        <Separator />
      </li>
      <li className="flex items-center gap-1.5">
        <a className={linkClassName} href={PROJECTS}>
          Projects
        </a>
        <Separator />
      </li>
      {/* The current page is not a link, and says so. */}
      <li aria-current="page" className="text-ink">
        {product}
      </li>
    </ol>
  </nav>
);
