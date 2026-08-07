export const siteConfig = {
  author: "Matthew Blode",
  description:
    "Rubber Duck is a macOS menu bar voice coding agent. Ask questions out loud, hear answers back, and understand unfamiliar code faster. Bring your own API key.",
  links: {
    author: "https://blode.co",
    github: "https://github.com/mblode/rubber-duck",
  },
  name: "Rubber Duck",
  title: "Rubber Duck | Talk through your code with AI",
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
export const faqId = `${siteConfig.url}/#faq`;
export const webPageId = `${siteConfig.url}/#webpage`;
export const breadcrumbId = `${siteConfig.url}/#breadcrumb`;

export const breadcrumbSchema = () => ({
  "@id": breadcrumbId,
  "@type": "BreadcrumbList",
  itemListElement: [
    { "@type": "ListItem", item: `${host}/`, name: "Home", position: 1 },
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
