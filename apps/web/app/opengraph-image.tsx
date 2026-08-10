import { renderZoneOgImage } from "@/app/og-image-shared";
import { siteConfig } from "@/lib/config";

export {
  OG_CONTENT_TYPE as contentType,
  OG_SIZE as size,
} from "@/app/og-image-shared";

export const alt = "Rubber Duck: talk through your code with AI";

/**
 * The house card (Rule 12), replacing the bespoke dark ImageResponse.
 */
export default function OpengraphImage() {
  return renderZoneOgImage({
    badge: "RUBBER-DUCK",
    eyebrow: "blode.co/rubber-duck",
    subtitle: "Talk through your code with AI.",
    title: siteConfig.name,
  });
}
