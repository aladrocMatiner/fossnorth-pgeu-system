.PHONY: preflight keycloak-realm sso-up sso-rebuild sso-down sso-logs web-shell

preflight:
	./scripts/preflight-check.sh

keycloak-realm:
	./scripts/generate-keycloak-realm.sh

# Build and start full stack with SSO enabled (runs preflight + realm generation)
sso-up: preflight keycloak-realm
	docker compose up -d --build

# Force a clean rebuild of images and restart everything
sso-rebuild: preflight keycloak-realm
	docker compose down
	docker compose build --no-cache
	docker compose up -d

# Stop containers (keeps volumes)
sso-down:
	docker compose down

# Follow logs for web and keycloak services
sso-logs:
	docker compose logs -f web keycloak

# Drop into a shell inside the web container
web-shell:
	docker compose exec web sh

