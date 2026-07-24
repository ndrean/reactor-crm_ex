// Cloudflare Email Worker — forwards incoming emails to the CRM webhook
//
// Setup:
// 1. Create a Worker in Cloudflare dashboard
// 2. Paste the `postal-mime` ESM library into a new file "postal-mime.js"
// 3. Paste this code into "index.js"
// 4. Add environment variable: EMAIL_WEBHOOK_SECRET (shared with the VPS, never sent over the wire)
// 5. In Email Routing, route admin@nlex.uk to this worker

// copy https://cdn.jsdelivr.net/npm/postal-mime@2.7.5/+esm into ./portal-mime.js

import PostalMime from "./postal-mime.js";

async function signPayload(body, secret) {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(body));
  const hex = [...new Uint8Array(signature)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return `sha256=${hex}`;
}

export default {
  async email(message, env, ctx) {
    const rawEmail = await new Response(message.raw).arrayBuffer();

    // Tell postal-mime to output attachments as Base64 strings:
    const parsed = await PostalMime.parse(rawEmail, {
      attachmentEncoding: "base64",
    });

    // Map attachments into a clean array for JSON, skip oversized (>13.4MB base64 ≈ 10MB binary)
    const MAX_B64_LENGTH = 13_400_000;
    const attachments = (parsed.attachments || [])
      .filter((att) => typeof att.content === "string" && att.content.length <= MAX_B64_LENGTH)
      .map((att) => ({
        filename: att.filename || "file",
        mimeType: att.mimeType,
        content: att.content,
      }));

    const body = JSON.stringify({
      from: message.from,
      subject: message.headers.get("subject") || parsed.subject || "",
      body: parsed.text || parsed.html || "",
      attachments: attachments,
    });

    const signature = await signPayload(body, env.EMAIL_WEBHOOK_SECRET);

    const resp = await fetch("https://reactor.nlex.uk/webhook/email", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-webhook-signature": signature,
      },
      body: body,
    });

    if (!resp.ok) {
      throw new Error(`Webhook rejected: ${resp.status} ${resp.statusText}`);
    }
  },
};