# Production Deploy Checklist

## Pre-deploy

- [ ] Set `PHX_HOST` and `SITE_ADDRESS` to your production domain in `.env-docker`
- [ ] Both values must match (e.g., `crm.example.com`)
- [ ] Create Docker secrets: `deploy.sh --secrets-from .env-docker`
- [ ] Configure Cloudflare (see `docs/cloudflare-setup.md`)
- [ ] If using DNS-01 challenge: create Cloudflare API token with Zone:DNS:Edit permission

## Deploy

```bash
deploy.sh --secrets-from .env-docker && deploy.sh --migrate
```

## Post-deploy verification

- [ ] Verify both replicas running: `docker service ps crm_app`
- [ ] Check health: `curl -fs https://yourdomain.com/api/health`
- [ ] Test WebSocket: open browser, verify LiveView connects (no flash of disconnect)
- [ ] Test Telegram webhook: send a message, verify response arrives
- [ ] Verify ETS cache sync:
  1. Toggle a workflow subscription on `/admin/workflows`
  2. Check app logs for `CacheListener: reloading SubscriptionCache` on both replicas
- [ ] Create admin account if first deploy: `docker exec <container> /app/bin/admin create_admin email password`

## Rollback

If issues are detected:

```bash
docker service rollback crm_app
```

The `update_config.failure_action: rollback` ensures automatic rollback on failed health checks.
