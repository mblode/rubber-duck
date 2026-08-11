import {
  OG_CONTENT_TYPE,
  OG_SIZE,
  renderZoneOgImage,
} from "@/app/og-image-shared";
import { siteConfig } from "@/lib/config";

export const contentType = OG_CONTENT_TYPE;
export const size = OG_SIZE;

export const alt = "Rubber Duck: voice coding for macOS";

/**
 * The house card (Rule 12), replacing the bespoke dark ImageResponse.
 */
export default function OpengraphImage() {
  return renderZoneOgImage({
    badge: "RUBBER-DUCK",
    eyebrow: "blode.co/rubber-duck",
    subtitle: "Say the problem. Fix the code.",
    title: siteConfig.name,
  });
}
