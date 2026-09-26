import {
  app,
  HttpRequest,
  HttpResponseInit,
  InvocationContext,
} from "@azure/functions";
import {
  BlobSASPermissions,
  generateBlobSASQueryParameters,
  SASProtocol,
  StorageSharedKeyCredential,
} from "@azure/storage-blob";
import { authenticate } from "../shared/auth";
import { getBlobServiceClient, IMAGES_CONTAINER } from "../shared/storage";
import { SasResponse } from "../shared/types";

const UUID =
  "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}";

// Issue #91: a SAS is only ever issued for a blob path the app actually uses.
// Each family is enumerated here on purpose. Do NOT collapse these into a
// generic `[a-z]+/{uuid}.jpg`: every new family is a new place a holder of
// the shared key can write, so it has to be added deliberately.
//
// Every family is anchored, has no leading slash, exactly one segment below a
// fixed prefix, a UUID name (so no traversal), and .jpg only.
const BLOB_PATH_PATTERNS: readonly RegExp[] = [
  // SPEC.md §7.3: an exercise's machine photo, exercises/{exerciseId}.jpg.
  new RegExp(`^exercises/${UUID}\\.jpg$`),
  // Issue #141: the photo attached to an exercise report,
  // reports/{reportId}.jpg, where reportId is the ExerciseReport UUID.
  new RegExp(`^reports/${UUID}\\.jpg$`),
];

function isAllowedBlobPath(path: string): boolean {
  return BLOB_PATH_PATTERNS.some((pattern) => pattern.test(path));
}

function getStorageCredential(): StorageSharedKeyCredential {
  const connectionString = process.env.STORAGE_CONNECTION_STRING;
  if (!connectionString) {
    throw new Error("STORAGE_CONNECTION_STRING not configured");
  }

  // Parse account name and key from connection string
  const accountNameMatch = connectionString.match(/AccountName=([^;]+)/);
  const accountKeyMatch = connectionString.match(/AccountKey=([^;]+)/);

  if (!accountNameMatch || !accountKeyMatch) {
    throw new Error("Could not parse storage account credentials");
  }

  return new StorageSharedKeyCredential(
    accountNameMatch[1],
    accountKeyMatch[1]
  );
}

app.http("imagesSas", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "images/sas",
  handler: async (
    request: HttpRequest,
    context: InvocationContext
  ): Promise<HttpResponseInit> => {
    const authError = authenticate(request);
    if (authError) return authError;

    const path = request.query.get("path");
    const mode = request.query.get("mode") as "upload" | "download" | null;

    if (!mode || !["upload", "download"].includes(mode)) {
      return {
        status: 400,
        jsonBody: {
          error:
            'Missing or invalid query params: path (string), mode ("upload" | "download")',
        },
      };
    }

    if (!path || !isAllowedBlobPath(path)) {
      return {
        status: 400,
        jsonBody: {
          error:
            'Invalid path: must match "exercises/{exerciseId}.jpg" or ' +
            '"reports/{reportId}.jpg", where the id is a UUID',
        },
      };
    }

    try {
      const credential = getStorageCredential();
      const blobServiceClient = getBlobServiceClient();
      const containerClient =
        blobServiceClient.getContainerClient(IMAGES_CONTAINER);
      const blobClient = containerClient.getBlobClient(path);

      const expiryMinutes = mode === "upload" ? 15 : 60;
      const expiresOn = new Date(Date.now() + expiryMinutes * 60 * 1000);

      const permissions = new BlobSASPermissions();
      if (mode === "upload") {
        permissions.write = true;
        permissions.create = true;
      } else {
        permissions.read = true;
      }

      const sasToken = generateBlobSASQueryParameters(
        {
          containerName: IMAGES_CONTAINER,
          blobName: path,
          permissions,
          expiresOn,
          protocol: SASProtocol.Https,
        },
        credential
      ).toString();

      const sasUrl = `${blobClient.url}?${sasToken}`;

      const response: SasResponse = {
        sasUrl,
        expiresAt: expiresOn.toISOString(),
      };

      return { jsonBody: response };
    } catch (error) {
      context.error("Images SAS error:", error);
      return {
        status: 500,
        jsonBody: { error: "Failed to generate SAS token" },
      };
    }
  },
});
