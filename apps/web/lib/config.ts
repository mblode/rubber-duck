export const siteConfig = {
  author: "Matthew Blode",
  description:
    "Ask about a repo out loud. Rubber Duck reads the code, answers back, and makes edits on your Mac.",
  links: {
    author: "https://blode.co",
    github: "https://github.com/mblode/rubber-duck",
  },
  name: "Rubber Duck",
  // `Product: what it does`, under 60 characters so the SERP does not truncate
  // it. Colon, never a pipe or an em dash.
  title: "Rubber Duck: voice coding for macOS",
  url: "https://blode.co/rubber-duck",
} as const;

/**
 * Stable schema.org node ids. Each entity is defined once in the root layout's
 * `@graph` and referenced by `@id` from anywhere else, so crawlers resolve one
 * graph instead of several disconnected snippets.
 *
 * The Person, WebSite and Organization ids belong to blode.co and are only ever
 * referenced here, never redefined. blode.co/rubber-duck is a path on blode.co
 * behind a rewrite, not a site of its own: a `blode.co/rubber-duck/#person`
 * publishes a second Matthew Blode on the same domain and splits the entity.
 * Contract: blode-co/apps/web/.claude/knowledge/zone-conventions.md
 */
const host = "https://blode.co";

export const personId = `${host}/#person`;
export const websiteId = `${host}/#website`;
export const orgId = `${host}/#organization`;

// Zone-local nodes keep the zone in the id.
export const appId = `${siteConfig.url}/#software`;
export const webPageId = `${siteConfig.url}/#webpage`;
export const breadcrumbId = `${siteConfig.url}/#breadcrumb`;

/**
 * The root crumb is named for the person, not "Home", and
 * `components/zone-breadcrumb.tsx` renders the same three names visibly.
 * Google treats a mismatch between the two as a markup error, so they change
 * together.
 */
export const breadcrumbSchema = () => ({
  "@id": breadcrumbId,
  "@type": "BreadcrumbList",
  itemListElement: [
    {
      "@type": "ListItem",
      item: `${host}/`,
      name: "Matthew Blode",
      position: 1,
    },
    {
      "@type": "ListItem",
      item: `${host}/projects`,
      name: "Projects",
      position: 2,
    },
    {
      "@type": "ListItem",
      item: siteConfig.url,
      name: siteConfig.name,
      position: 3,
    },
  ],
});
