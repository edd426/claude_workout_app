import { BlobServiceClient } from "@azure/storage-blob";

let blobServiceClient: BlobServiceClient | null = null;

export const IMAGES_CONTAINER = "workout-images";

export function getBlobServiceClient(): BlobServiceClient {
  if (!blobServiceClient) {
    const connectionString = process.env.STORAGE_CONNECTION_STRING;
    if (!connectionString) {
      throw new Error("STORAGE_CONNECTION_STRING not configured");
    }
    blobServiceClient =
      BlobServiceClient.fromConnectionString(connectionString);
  }
  return blobServiceClient;
}
