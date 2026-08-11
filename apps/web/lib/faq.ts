import { faqId, siteConfig, websiteId } from "@/lib/config";

/**
 * One source for the FAQ, read by both the rendered section and the FAQPage
 * JSON-LD. Hand-writing the schema separately from the copy is how the two
 * drift apart, and the schema is the half nobody proofreads.
 */
export interface FaqEntry {
  answer: string;
  /** Shell command shown under the answer, and appended to the schema answer. */
  code?: string;
  /**
   * Anchor slug. Rendered as the `id` on the question's own `<h3>`, so the URL
   * in `acceptedAnswer.url` lands on something that exists and is visible
   * without opening anything. Hand-written rather than derived from the
   * question, so rewording a question cannot silently break an inbound link.
   */
  id: string;
  question: string;
}

/** The two remaining pre-install objections: unprompted edits and connectivity. */
export const faq: FaqEntry[] = [
  {
    // The question the honest answer costs least on. Every hedge here reads as
    // a hedge, and a reader who installs it and then finds `edit_file` for
    // themselves stops believing the rest of the page.
    //
    // Shortened but not softened: safe mode is still named, and it is still off
    // by default in the same sentence. The scoping clause went because the tool
    // table says it two sections up, in stronger words.
    answer:
      "Yes. edit_file and write_file are real tools and there is no per-edit prompt: ask it to fix something and it fixes it, then tells you what it changed. Safe mode refuses both and is off by default. Keep the repo in git.",
    id: "edits",
    question: "Can it change my files without asking?",
  },
  {
    answer:
      "No. The conversation runs through the OpenAI Realtime API, so it needs a connection. The tools run locally either way, but nothing decides which to call without a model.",
    id: "offline",
    question: "Does Rubber Duck work offline?",
  },
];

const anchor = (entry: FaqEntry) => `${siteConfig.url}#${entry.id}`;

/**
 * A single FAQPage node for the layout's `@graph`. One per page is the limit,
 * and `isPartOf` is what ties it to the WebSite rather than leaving it as a
 * disconnected snippet.
 */
export const faqSchema = () => ({
  "@id": faqId,
  "@type": "FAQPage",
  inLanguage: "en",
  isPartOf: { "@id": websiteId },
  mainEntity: faq.map((entry) => ({
    "@id": anchor(entry),
    "@type": "Question",
    acceptedAnswer: {
      "@type": "Answer",
      text: entry.code ? `${entry.answer} ${entry.code}` : entry.answer,
      url: anchor(entry),
    },
    name: entry.question,
  })),
  name: `${siteConfig.name} questions`,
  url: siteConfig.url,
});
