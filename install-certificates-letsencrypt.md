# Let's Encrypt Certificate (DNS Challenge) for fossnorth.aladroc.io

This guide walks through issuing a Let’s Encrypt certificate for
`fossnorth.aladroc.io` using the DNS-01 challenge and wiring it into
HAProxy.

## 1. Prerequisites
- Root/sudo access on the host that terminates TLS (the HAProxy server).
- Ability to create DNS TXT records for `aladroc.io`.
- Port 80/443 available on the HAProxy host (80 used only for redirects).
- Email address for Let’s Encrypt notifications (expiry, issues).

## 2. Install Certbot
Modern Ubuntu/Debian systems should install Certbot via Snap:

```bash
sudo apt-get update
sudo apt-get install -y snapd
sudo snap install core && sudo snap refresh core
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot
```

> Alternative: `apt-get install certbot` (may lag behind). Snap ensures
> you get the DNS manual plugin without extra steps.

## 3. Request the Certificate (DNS-01)
Run Certbot in *manual* DNS mode:

```bash
sudo certbot certonly \
  --manual \
  --preferred-challenges dns \
  --email infra@aladroc.io \
  --no-eff-email \
  --agree-tos \
  -d fossnorth.aladroc.io
```

Certbot output will show something like:

```
Please deploy a DNS TXT record under the name
_acme-challenge.fossnorth.aladroc.io with the following value:

   abc123...token...

Before continuing, verify the record is deployed.
```

1. Go to your DNS provider.
2. Create a TXT record named `_acme-challenge.fossnorth.aladroc.io`
   containing the provided token.
3. Wait for propagation (usually a minute or two). Verify from a second
   terminal:
   ```bash
   dig TXT _acme-challenge.fossnorth.aladroc.io
   ```
4. Press **Enter** back in the Certbot session to let it validate.

When validation succeeds you’ll see:
```
Congratulations! Your certificate and chain have been saved at:
  /etc/letsencrypt/live/fossnorth.aladroc.io/fullchain.pem
  /etc/letsencrypt/live/fossnorth.aladroc.io/privkey.pem
```

## 4. Prepare Files for HAProxy
HAProxy expects the certificate chain and private key in a single `.pem`.

```bash
sudo mkdir -p /etc/haproxy/certs
sudo bash -c 'cat /etc/letsencrypt/live/fossnorth.aladroc.io/fullchain.pem \
  /etc/letsencrypt/live/fossnorth.aladroc.io/privkey.pem \
  > /etc/haproxy/certs/fossnorth.aladroc.io.pem'
sudo chmod 600 /etc/haproxy/certs/fossnorth.aladroc.io.pem
sudo chown root:root /etc/haproxy/certs/fossnorth.aladroc.io.pem
```

## 5. HAProxy Configuration
Add (or edit) the HTTPS frontend, typically in `/etc/haproxy/haproxy.cfg`.

```cfg
frontend https-in
    bind *:443 ssl crt /etc/haproxy/certs/fossnorth.aladroc.io.pem
    mode http
    option httplog
    acl host_pgeu hdr(host) -i fossnorth.aladroc.io
    use_backend pgeu_web if host_pgeu
    default_backend pgeu_web
    http-response set-header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"

frontend http-in
    bind *:80
    mode http
    redirect scheme https code 301 if !{ ssl_fc }

backend pgeu_web
    mode http
    balance roundrobin
    option httpchk GET /healthz
    server web1 127.0.0.1:8000 check
```

- Adjust backend servers/health checks to match your deployment.
- Ensure the HTTPS frontend references the `.pem` you created.

Validate and reload HAProxy:

```bash
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl reload haproxy
```

## 6. Renewal Strategy
Manual DNS challenges require updating TXT records every 90 days. To
automate:

- Use a Certbot DNS plugin (`python3-certbot-dns-cloudflare`, etc.) if
  your provider is supported. Example:
  ```bash
  sudo apt-get install python3-certbot-dns-cloudflare
  sudo certbot certonly --dns-cloudflare --dns-cloudflare-credentials ~/.secrets/cloudflare.ini -d fossnorth.aladroc.io
  ```
- Alternatively, script TXT updates via API (using `acme.sh`,
  `lego`, or Terraform).

After renewal completes, re-build the HAProxy `.pem` and reload:

```bash
sudo bash -c 'cat /etc/letsencrypt/live/fossnorth.aladroc.io/fullchain.pem \
  /etc/letsencrypt/live/fossnorth.aladroc.io/privkey.pem \
  > /etc/haproxy/certs/fossnorth.aladroc.io.pem'
sudo systemctl reload haproxy
```

## 7. Verification
- `curl -I https://fossnorth.aladroc.io` should show `HTTP/1.1 200` and
  the correct certificate chain (check with `openssl s_client -connect fossnorth.aladroc.io:443 -servername fossnorth.aladroc.io`).
- Review `/var/log/haproxy.log` for any TLS errors.

You now have a valid Let’s Encrypt certificate protecting
`fossnorth.aladroc.io` with HAProxy terminating TLS.
