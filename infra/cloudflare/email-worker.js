// Cloudflare Email Worker — forwards incoming emails to the CRM webhook
//
// Setup:
// 1. Create a Worker in Cloudflare dashboard
// 2. Paste the `postal-mime` ESM library into a new file "postal-mime.js"
// 2. Paste this code into "index.js"
// 3. Add environment variable: EMAIL_WEBHOOK_SECRET (same value as on the VPS)
// 4. In Email Routing, route admin@nlex.uk to this worker

// copy https://cdn.jsdelivr.net/npm/postal-mime@2.7.5/+esm into ./portal-mime.js


import PostalMime from "./postal-mime.js";

export default {
  async email(message, env, ctx) {
    const rawEmail = await new Response(message.raw).arrayBuffer()
    
    // Tell postal-mime to output attachments as Base64 strings:
    const parsed = await PostalMime.parse(rawEmail, {
      attachmentEncoding: "base64"
    });

    // Map attachments into a clean array for JSON
    const attachments = (parsed.attachments || []).map((att) => ({
      filename: att.filename || "file",
      mimeType: att.mimeType,
      content: att.content // Now a Base64 string!
    }));

    const resp = await fetch("https://reactor.nlex.uk/webhook/email", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-email-secret": env.EMAIL_WEBHOOK_SECRET,
      },
      body: JSON.stringify({
        from: message.from,
        subject: message.headers.get("subject") || parsed.subject || "",
        body: parsed.text || parsed.html || "",
        attachments: attachments,
      }),
    });

    if (!resp.ok) {
      throw new Error(`Webhook rejected: ${resp.status} ${resp.statusText}`);
    }
  },
};