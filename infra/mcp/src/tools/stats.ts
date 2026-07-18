/**
 * Read-only stats + calendar tools — issue #79.
 * Aggregation happens server-side in the Functions API; these are thin
 * wrappers.
 */

import { apiGet } from "../shared/http.js";
import type { Stats, CalendarEntry } from "../shared/types.js";

export async function getStats(options?: {
  startDate?: string;
  endDate?: string;
}): Promise<Stats> {
  return apiGet<Stats>("stats", {
    startDate: options?.startDate,
    endDate: options?.endDate,
  });
}

export async function getCalendar(
  startDate: string,
  endDate: string
): Promise<CalendarEntry[]> {
  const { days } = await apiGet<{ days: CalendarEntry[] }>("calendar", {
    startDate,
    endDate,
  });
  return days;
}
