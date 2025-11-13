FROM python:3.10-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    DJANGO_SETTINGS_MODULE=postgresqleu.settings \
    LANG=C.UTF-8

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential \
      libpq-dev \
      libjpeg-dev \
      libfreetype6-dev \
      libpng-dev \
      libcairo2 \
      libpango-1.0-0 \
      libpangocairo-1.0-0 \
      libmagic1 \
      libffi-dev \
      libssl-dev \
      fonts-dejavu-core && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY pgeu-system /app

RUN pip install --upgrade pip && \
    pip install -r tools/devsetup/dev_requirements.txt

COPY docker-compose/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8000

ENTRYPOINT ["/entrypoint.sh"]
CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]
