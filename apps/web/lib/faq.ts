import { faqId, siteConfig, websiteId } from "@/lib/config";

/**
 * One source for the FAQ, read by both the rendered accordion and the FAQPage
 * JSON-LD. Hand-writing the schema separately from the copy is how the two
 * drift apart, and the schema is the half nobody proofreads.
 */
export interface FaqEntry {
  answer: string;
  /** Shell command shown under the answer, and appended to the schema answer. */
  code?: string;
  /**
   * Anchor slug. Rendered as the `id` on the question's own `<details>`, so the
   * URL in `acceptedAnswer.url` lands on something that exists and is visible
   * without opening anything. Hand-written rather than derived from the
   * question, so rewording a question cannot silently break an inbound link.
   */
  id: string;
  question: string;
}

export const faq: FaqEntry[] = [
  {
    answer:
      "It can open the files you are asking about. Point the duck command at a directory and the menu bar app switches to that workspace straight away. From there it reads files, greps the tree, finds files by name, runs commands, and makes edits.",
    id: "vs-chat",
    question: "How is this different from a chat window?",
  },
  {
    answer:
      "Locally. The tools run through a small daemon over a Unix socket, so your own machine is what opens a file, not a remote sandbox. What the model asked for does go back to it as the tool result, the same as any other API call on your key.",
    id: "code-access",
    question: "Where does my code get read?",
  },
  {
    answer:
      "No. Audio goes to the OpenAI Realtime API at 24 kHz mono on your own key, kept in the macOS Keychain, and you pay for the minutes you talk.",
    id: "subscription",
    question: "Do I need a subscription?",
  },
  {
    answer:
      "The app still works, you just get the conversation without the tools. The command line half installs itself the first time you launch the app.",
    id: "daemon",
    question: "What if the daemon is not running?",
  },
  {
    answer:
      "Option+D activates the voice agent. Option+Shift+D opens Settings. Both rebind in Settings.",
    id: "shortcuts",
    question: "What are the shortcuts?",
  },
  {
    answer:
      "Download the DMG from the latest GitHub release, or install from the Homebrew tap. Requires macOS 15.2 or later.",
    code: "brew install --cask mblode/tap/rubber-duck",
    id: "install",
    question: "How do I install it?",
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
