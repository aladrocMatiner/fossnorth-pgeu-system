Here are the relevant URLs for this setup:

- App: http://localhost:8000/
  - Login: http://localhost:8000/accounts/login/
  - Admin: http://localhost:8000/admin/
- Keycloak realm base (OIDC): http://127.0.0.1:8080/realms/pgeu
- Keycloak admin console: http://127.0.0.1:8080/admin/ (default credentials: admin/admin)
- Keycloak health: http://127.0.0.1:9000/health/ready
- SSO redirect endpoint in app: http://localhost:8000/accounts/login/keycloak/
