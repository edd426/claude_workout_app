/**
 * The snapshot sync metadata doc (`syncMeta` container, id "snapshot").
 *
 * Shared by the snapshot endpoints, which write it, and the v5 read endpoints,
 * which use it to tell "the phone has not mirrored this yet" apart from "the
 * user has none" — the same distinction the snapshot GET draws for restore.
 */

// "../shared/cosmos", not "./cosmos": jest.config.js swaps in the Cosmos mock
// by matching the import string against `.*/shared/cosmos`, and "./cosmos"
// would silently load the real client in tests.
import { getDatabase } from "../shared/cosmos";
import { readItemOrNull } from "./readHelpers";
import { SyncMetaDoc, V5_SCHEMA_VERSION } from "./types";

export const SYNC_META_CONTAINER = "syncMeta";
export const SYNC_META_ID = "snapshot";

export async function readSyncMeta(): Promise<SyncMetaDoc | null> {
  return readItemOrNull<SyncMetaDoc>(
    getDatabase().container(SYNC_META_CONTAINER),
    SYNC_META_ID
  );
}

/**
 * True once a v5 push has succeeded at least once. Until then the v5
 * containers hold nothing the phone has confirmed, so no reader may present
 * their contents (or their emptiness) as the user's data.
 */
export function hasV5Mirror(meta: SyncMetaDoc | null): boolean {
  return (meta?.highestSchemaVersion ?? 0) >= V5_SCHEMA_VERSION;
}
