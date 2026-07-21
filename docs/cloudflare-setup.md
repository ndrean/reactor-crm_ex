# Cloudflare Configuration Checklist

Settings to configure in the Cloudflare dashboard after adding your domain.

## DNS

- [ ] Add **A record** pointing to VPS IP address
- [ ] Set proxy status to **Proxied** (orange cloud)

## SSL/TLS

- [ ] Set encryption mode to **Full**
- [ ] After confirming Let's Encrypt certs work through Caddy, upgrade to **Full (Strict)**

## Network

- [ ] Enable **WebSockets** toggle

## Speed > Optimization

- [ ] Disable **Rocket Loader** (interferes with Phoenix LiveView JS)
- [ ] Disable **Mirage** (if available — can interfere with inline images)

## Notes

- Phoenix heartbeat interval (30s) is well under Cloudflare's WebSocket timeout (~100s) — no tuning needed
- Caddy auto-provisions Let's Encrypt certificates when `SITE_ADDRESS` is set to a real domain
- With `endpoint_mode: dnsrr`, Caddy sees individual replica IPs and `lb_policy cookie` works correctly
