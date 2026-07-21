// Cloudflare Email Worker — forwards incoming emails to the CRM webhook
//
// Setup:
// 1. Create a Worker in Cloudflare dashboard
// 2. Paste this code
// 3. Add environment variable: EMAIL_WEBHOOK_SECRET (same value as on the VPS)
// 4. In Email Routing, route admin@nlex.uk to this worker

export default {
  async email(message, env, ctx) {
    const raw = await new Response(message.raw).text();

    // Extract plain text body from multipart email
    const body = extractPlainText(raw);

    await fetch("https://reactor.nlex.uk/webhook/email", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-email-secret": env.EMAIL_WEBHOOK_SECRET,
      },
      body: JSON.stringify({
        from: message.from,
        subject: message.headers.get("subject") || "",
        body: body,
      }),
    });
  },
};

function extractPlainText(raw) {
  // Find boundary in Content-Type header
  const boundaryMatch = raw.match(/boundary="?([^"\r\n]+)"?/);

  if (boundaryMatch) {
    // Multipart: find the text/plain part
    const boundary = boundaryMatch[1];
    const parts = raw.split("--" + boundary);
    for (const part of parts) {
      if (part.includes("Content-Type: text/plain")) {
        // Body starts after the double newline
        const bodyStart = part.indexOf("\r\n\r\n") ?? part.indexOf("\n\n");
        if (bodyStart !== -1) {
          return part.substring(bodyStart + 4).trim();
        }
      }
    }
  }

  // Not multipart: just strip headers
  const sep = raw.indexOf("\r\n\r\n");
  if (sep !== -1) return raw.substring(sep + 4).trim();
  const altSep = raw.indexOf("\n\n");
  if (altSep !== -1) return raw.substring(altSep + 2).trim();
  return raw;
}
