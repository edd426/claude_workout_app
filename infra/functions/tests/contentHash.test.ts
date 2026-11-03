/** Canonical JSON and content hashing for snapshot reconciliation (#166 scaling). */

import { createHash } from "node:crypto";
import {
  canonicalJson,
  clientContent,
  contentHash,
  CONTENT_HASH_FIELD,
} from "../src/shared/contentHash";

describe("canonicalJson", () => {
  test("sorts object keys at every depth and keeps array order", () => {
    expect(canonicalJson({ b: 1, a: { d: [3, 1, { z: 0, y: 1 }], c: null } })).toBe(
      '{"a":{"c":null,"d":[3,1,{"y":1,"z":0}]},"b":1}'
    );
  });

  test("is JSON for scalars, escaping strings exactly like JSON.stringify", () => {
    expect(canonicalJson("Lég \"press\"\n")).toBe(JSON.stringify("Lég \"press\"\n"));
    expect(canonicalJson(82.5)).toBe("82.5");
    expect(canonicalJson(true)).toBe("true");
    expect(canonicalJson(null)).toBe("null");
  });

  test("an undefined member is left out, as JSON would", () => {
    expect(canonicalJson({ a: undefined, b: 2 })).toBe('{"b":2}');
  });

  test("distinguishes a string from a number and an empty array from an empty object", () => {
    expect(canonicalJson({ a: "1" })).not.toBe(canonicalJson({ a: 1 }));
    expect(canonicalJson({ a: [] })).not.toBe(canonicalJson({ a: {} }));
  });
});

describe("contentHash", () => {
  test("is the sha256 hex of the canonical JSON", () => {
    const doc = { id: "w1", name: "Push" };
    expect(contentHash(doc)).toBe(
      createHash("sha256").update('{"id":"w1","name":"Push"}').digest("hex")
    );
  });

  test("ignores Cosmos system fields and the hash field itself", () => {
    const plain = { id: "w1", name: "Push" };
    const decorated = {
      ...plain,
      _rid: "r",
      _self: "s",
      _etag: "e",
      _attachments: "a",
      _ts: 1,
      [CONTENT_HASH_FIELD]: "forged",
    };
    expect(contentHash(decorated)).toBe(contentHash(plain));
    expect(clientContent(decorated)).toEqual(plain);
  });

  test("the field is mirrorContentHash, outside Cosmos's _ system namespace", () => {
    expect(CONTENT_HASH_FIELD).toBe("mirrorContentHash");
  });

  test("keeps other underscore fields: they are client content", () => {
    expect(contentHash({ id: "w1", _note: "x" })).not.toBe(contentHash({ id: "w1" }));
  });
});
