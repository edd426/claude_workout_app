import {
  app,
  HttpRequest,
  HttpResponseInit,
  InvocationContext,
} from "@azure/functions";
import {
  BlobSASPermissions,
  generateBlobSASQueryParameters,
  StorageSharedKeyCredential,
} from "@azure/storage-blob";
import { authenticate } from "../shared/auth";
import { getBlobServiceClient, IMAGES_CONTAINER } from "../shared/storage";
import { SasResponse } from "../shared/types";

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
    _context: InvocationContext
  ): Promise<HttpResponseInit> => {
    const authError = authenticate(request);
    if (authError) return authError;

    const path = request.query.get("path");
    const mode = request.query.get("mode") as "upload" | "download" | null;

    if (!path || !mode || !["upload", "download"].includes(mode)) {
      return {
        status: 400,
        jsonBody: {
          error:
            'Missing or invalid query params: path (string), mode ("upload" | "download")',
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
      return {
        status: 500,
        jsonBody: { error: "Failed to generate SAS token" },
      };
    }
  },
});
