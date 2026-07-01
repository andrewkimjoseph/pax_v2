import * as crypto from "crypto";
import { logger } from "firebase-functions/v2";

export interface DecryptPrivateKeyOptions {
  logPrefix?: "V1" | "V2";
}

function decryptPrivateKeyCore(
  encryptedJson: string,
  sessionKey: string,
  logPrefix?: "V1" | "V2"
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
    const authTag = ciphertext.subarray(-authTagLength);
    const actualCiphertext = ciphertext.subarray(0, -authTagLength);

    decipher.setAuthTag(authTag);

    let decrypted = decipher.update(actualCiphertext, undefined, "utf8");
    decrypted += decipher.final("utf8");

    return decrypted;
  } catch (error) {
    const prefix = logPrefix ? `[${logPrefix}] ` : "[V2] ";
    logger.error(`${prefix}Failed to decrypt private key`, { error });
    throw new Error(
      "Decryption failed. The encrypted key may be from a different " +
        "session or corrupted."
    );
  }
}

/**
 * Decrypts a private key encrypted by KeyEncryptionService.
 * Returns normalized private key hex (0x-prefixed).
 */
export function decryptPrivateKey(
  encryptedJson: string,
  sessionKey: string,
  options?: DecryptPrivateKeyOptions
): string {
  let privateKeyHex = decryptPrivateKeyCore(
    encryptedJson,
    sessionKey,
    options?.logPrefix
  );
  if (!privateKeyHex.startsWith("0x")) {
    privateKeyHex = `0x${privateKeyHex}`;
  }
  return privateKeyHex;
}
