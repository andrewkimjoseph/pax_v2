import * as crypto from "crypto";
import {logger} from "firebase-functions/v2";

/**
 * Decrypts a private key that was encrypted using KeyEncryptionService.
 * Uses AES-GCM with PBKDF2 key derivation, matching Flutter implementation.
 * @param {string} encryptedJson - Encrypted JSON string from Flutter
 * @param {string} sessionKey - Session key (Firebase Auth token or Google ID)
 * @return {string} Decrypted private key hex string (without 0x prefix)
 */
export function decryptPrivateKey(
  encryptedJson: string,
  sessionKey: string
): string {
  try {
    const data = JSON.parse(encryptedJson);

    if (data.version !== 1) {
      throw new Error("Unsupported encryption format version");
    }

    const salt = Buffer.from(data.salt, "base64");
    const iv = Buffer.from(data.iv, "base64");
    const ciphertext = Buffer.from(data.ciphertext, "base64");
    const iterations = data.iterations || 20000;
    const keyLength = 32;

    const key = crypto.pbkdf2Sync(
      Buffer.from(sessionKey, "utf8"),
      salt,
      iterations,
      keyLength,
      "sha256"
    );

    const decipher = crypto.createDecipheriv("aes-256-gcm", key, iv);

    const authTagLength = 16;
    const authTag = ciphertext.slice(-authTagLength);
    const actualCiphertext = ciphertext.slice(0, -authTagLength);

    decipher.setAuthTag(authTag);

    let decrypted = decipher.update(actualCiphertext, undefined, "utf8");
    decrypted += decipher.final("utf8");

    return decrypted;
  } catch (error) {
    logger.error("Failed to decrypt private key", {error});
    throw new Error(
      "Decryption failed. The encrypted key may be from a different " +
        "session or corrupted."
    );
  }
}
