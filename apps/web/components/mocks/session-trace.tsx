export const SessionTrace = () => (
  <figure className="mt-14 border-white/12 border-y py-8 sm:mt-20 sm:py-10">
    <blockquote className="max-w-[38ch] text-balance font-medium text-2xl text-ink tracking-[-0.02em] sm:text-3xl">
      “Why does the socket use a temp path?”
    </blockquote>
    <figcaption className="mt-5 max-w-[62ch] text-pretty text-base text-ink-muted sm:text-lg">
      Rubber Duck found the fallback in{" "}
      <code className="font-mono text-ink">cli/src/constants.ts</code> and added
      the log.
    </figcaption>
  </figure>
);
