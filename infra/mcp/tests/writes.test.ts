/**
 * Tests for `deleteInboxOperation` — issue #148.
 *
 * Terminal inbox operations (failed/rejected/applied) accumulate forever with
 * no way to clear them. This is a thin wrapper over `DELETE /api/inbox/{id}`
 * (the Functions API enforces the terminal-only rule); the tool layer's job
 * is id validation and all-or-nothing batching, mirroring
 * `resolveExerciseReport`.
 */

import { describe, it, expect, vi, beforeEach } from "vitest";

const mockApiDelete = vi.fn();

vi.mock("../src/shared/http.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../src/shared/http.js")>();
  return { ...actual, apiDelete: mockApiDelete };
});

const { deleteInboxOperation } = await import("../src/tools/writes.js");

beforeEach(() => {
  mockApiDelete.mockReset();
});

describe("deleteInboxOperation", () => {
  it("deletes a single operation by id", async () => {
    mockApiDelete.mockResolvedValue(undefined);

    const result = await deleteInboxOperation({ id: "op-1" });

    expect(result).toEqual({ deleted: ["op-1"] });
    expect(mockApiDelete).toHaveBeenCalledWith("inbox/op-1");
    expect(mockApiDelete).toHaveBeenCalledTimes(1);
  });

  it("deletes a batch of ids, all-or-nothing", async () => {
    mockApiDelete.mockResolvedValue(undefined);

    const result = await deleteInboxOperation({ ids: ["op-1", "op-2", "op-3"] });

    expect(result).toEqual({ deleted: ["op-1", "op-2", "op-3"] });
    expect(mockApiDelete).toHaveBeenCalledTimes(3);
    expect(mockApiDelete).toHaveBeenNthCalledWith(2, "inbox/op-2");
  });

  it("rejects ids and id given together rather than guessing", async () => {
    await expect(
      deleteInboxOperation({ id: "op-1", ids: ["op-2"] })
    ).rejects.toThrow(/either id or ids/);
    expect(mockApiDelete).not.toHaveBeenCalled();
  });

  it("rejects an empty ids array", async () => {
    await expect(deleteInboxOperation({ ids: [] })).rejects.toThrow(
      /at least one/
    );
    expect(mockApiDelete).not.toHaveBeenCalled();
  });

  it("requires an id", async () => {
    await expect(deleteInboxOperation({})).rejects.toThrow(
      /id must be a non-empty string/
    );
    expect(mockApiDelete).not.toHaveBeenCalled();
  });

  it("validates every id before deleting any of them", async () => {
    await expect(
      deleteInboxOperation({ ids: ["op-1", ""] })
    ).rejects.toThrow(/non-empty string/);
    // Nothing deleted: a half-applied batch is worse than a refused one.
    expect(mockApiDelete).not.toHaveBeenCalled();
  });

  it("surfaces a refused delete (409, e.g. a pending operation) without deleting batch-mates already validated", async () => {
    mockApiDelete
      .mockResolvedValueOnce(undefined)
      .mockRejectedValueOnce(new Error("Functions API returned 409: Cannot delete pending operation op-2"));

    await expect(
      deleteInboxOperation({ ids: ["op-1", "op-2", "op-3"] })
    ).rejects.toThrow(/409/);
    // op-1 already succeeded server-side before op-2 failed; the third id is
    // never attempted once a batch-mate errors.
    expect(mockApiDelete).toHaveBeenCalledTimes(2);
  });
});
