# Ansible Deployment Helper

This playbook automates the setup of [pgeu-system](https://github.com/pgeu/pgeu-system)
on a Debian/Ubuntu host. It follows the steps from `preliminar-install.md`:

1. Install system packages (git, Python build deps, PostgreSQL client libs, uwsgi, fonts, etc.).
2. Clone the upstream repository into `/opt/pgeu-system` (configurable).
3. Create and populate a Python virtual environment.
4. Render `postgresqleu/local_settings.py` with the supplied credentials.
5. Optionally provision the PostgreSQL role/database.
6. Run Django migrations and `collectstatic`.

## Control-Machine Requirements
1. Install Ansible and helpers (Debian/Ubuntu example):
   ```bash
   sudo apt-get update
   sudo apt-get install -y python3 python3-pip python3-venv git sshpass ansible
   ```
2. Install the PostgreSQL collection once (only needed if `pgeu_manage_database` is `true`):
   ```bash
   ansible-galaxy collection install community.postgresql
   ```
3. (Optional) Create a Python virtualenv for Ansible to keep dependencies isolated:
   ```bash
   python3 -m venv ~/.venvs/ansible
   . ~/.venvs/ansible/bin/activate
   pip install --upgrade pip ansible
   ```

## Target-Host Prerequisites
- Debian/Ubuntu host reachable over SSH.
- A user (e.g., `fossnorth`) with passwordless sudo (`/etc/sudoers.d/90-pgeu-system` entry such as `fossnorth ALL=(ALL) NOPASSWD:ALL`).
- SSH key copied to the host (`ssh-copy-id fossnorth@server`).
- Optional: pre-create `/opt/pgeu-system` owned by that user if you do not want Ansible to adjust ownership automatically.

## Inventory Setup
1. Create an inventory file (`inventory.ini`):
   ```ini
   [pgeu_hosts]
   fossnorth-pgeu-system ansible_host=192.0.2.10 ansible_user=fossnorth ansible_become=true
   ```
2. (Recommended) Add `group_vars/pgeu_hosts.yml` to hold persistent overrides:
   ```yaml
   pgeu_install_dir: /opt/pgeu-system
   pgeu_allowed_hosts:
     - conference.example.org
   pgeu_site_base_url: https://conference.example.org/
   pgeu_db_password: secure-db-pass
   pgeu_secret_key: "{{ lookup('password', 'secrets/pgeu_secret length=50 chars=ascii_letters,digits') }}"
   ```
3. Validate connectivity before running the play:
   ```bash
   ansible -i inventory.ini pgeu_hosts -m ping
   ```

## Usage
Run the playbook (override sensitive values via `-e` if you did not put them in vars files):

```bash
ansible-playbook -i inventory.ini ansible/install_pgeu_system.yml \
  -e "pgeu_secret_key=$(openssl rand -hex 32)" \
  -e "pgeu_allowed_hosts=['conference.example.org']" \
  -e "pgeu_server_email=noreply@example.org" \
  -e "pgeu_db_password=mysecret" \
  -e "pgeu_site_base_url=https://conference.example.org/"
```

Override any variable via `-e` or inventory/group vars. Notable settings (see
defaults inside `install_pgeu_system.yml`):

- `pgeu_install_dir`: where the app lives (default `/opt/pgeu-system`)
- `pgeu_system_user` / `pgeu_system_group`: owner of the files
- `pgeu_allowed_hosts`, `pgeu_site_base_url`, `pgeu_secret_key`, `pgeu_server_email`
- `pgeu_db_*`: database connection parameters
- `pgeu_manage_database`: set to `true` to let Ansible create the DB/user locally (requires passwordless access as `postgres`)
- `pgeu_run_migrations`, `pgeu_collectstatic`: toggle Django management commands

After the playbook completes, configure uwsgi/nginx and background services
(`tools/systemd/*.service`) as needed for your environment. Create a Django
superuser manually:

```bash
cd /opt/pgeu-system
sudo -u fossnorth ./venv/bin/python manage.py createsuperuser
```

## Troubleshooting
- **Missing Control Packages**: If `ansible-playbook` is not found, revisit the control-machine requirements above.
- **Inventory Issues**: Run `ansible-inventory -i inventory.ini --graph` to confirm hosts are in `pgeu_hosts`.
- **Failed package installs**: Ensure `apt` works on the target host and that any internal mirrors/proxies are configured.
- **Database creation failures**: Set `pgeu_manage_database: false` when the control node cannot become the `postgres` user, and create the DB manually instead.
