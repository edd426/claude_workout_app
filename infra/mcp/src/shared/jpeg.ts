/** Small helpers shared by the photo tools (get_report_photo, attach_exercise_photo). */

/**
 * The largest photo either tool moves, in raw bytes. Chosen so the base64
 * form stays within 5 MB, the Claude API's per-image limit. The phone sends
 * 1024px JPEGs of ~100–300 KB, so anything near this is not a normal photo.
 */
export const MAX_PHOTO_BYTES = 3_750_000;

/** JPEG files start with the SOI marker FF D8 followed by another FF. */
export function isJpeg(bytes: Uint8Array): boolean {
  return (
    bytes.length >= 3 &&
    bytes[0] === 0xff &&
    bytes[1] === 0xd8 &&
    bytes[2] === 0xff
  );
}

export function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} bytes`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

export async function discardBody(response: Response): Promise<void> {
  try {
    await response.body?.cancel();
  } catch {
    // Nothing useful to do; the error being thrown is what matters.
  }
}
