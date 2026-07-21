export default {
  async email(message, env, ctx) {
    const raw = await new Response(message.raw).text();
    await fetch("https://reactor.nlex.uk/admin/incoming-emails", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        from: message.from,
        to: message.to,
        body: raw,
      }),
    });
  },
} satisfies ExportedHandler<Env>;