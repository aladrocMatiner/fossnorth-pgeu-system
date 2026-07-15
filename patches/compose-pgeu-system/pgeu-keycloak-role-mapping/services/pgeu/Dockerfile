FROM python:3.10-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    DJANGO_SETTINGS_MODULE=postgresqleu.settings \
    LANG=C.UTF-8 \
    PGEU_APP_DIR=/app \
    VIRTUAL_ENV=/opt/pgeu/venv \
    PATH=/opt/pgeu/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      bash \
      build-essential \
      ca-certificates \
      curl \
      fonts-dejavu-core \
      git \
      libcairo2 \
      libffi-dev \
      libfreetype6-dev \
      libjpeg-dev \
      libmagic1 \
      libpango-1.0-0 \
      libpangocairo-1.0-0 \
      libpng-dev \
      libpq-dev \
      libssl-dev \
      netcat-openbsd \
      pkg-config \
      postgresql-client && \
    python -m venv /opt/pgeu/venv && \
    /opt/pgeu/venv/bin/pip install --upgrade pip setuptools wheel && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY services/pgeu/entrypoint.sh /usr/local/bin/pgeu-entrypoint
COPY services/pgeu/render-local-settings.py /usr/local/bin/pgeu-render-local-settings
RUN chmod +x /usr/local/bin/pgeu-entrypoint /usr/local/bin/pgeu-render-local-settings && \
    mkdir -p /var/lib/pgeu/staticfiles /var/lib/pgeu/media

EXPOSE 8000

ENTRYPOINT ["pgeu-entrypoint"]
CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]
