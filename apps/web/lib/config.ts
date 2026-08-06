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
 */
export const personId = `${siteConfig.url}/#person`;
export const websiteId = `${siteConfig.url}/#website`;
export const appId = `${siteConfig.url}/#software`;
export const faqId = `${siteConfig.url}/#faq`;
