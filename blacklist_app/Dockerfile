FROM public.ecr.aws/docker/library/python:3.11-slim

WORKDIR /app

# Instalar curl para el healthcheck
RUN apt-get update && apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/
COPY newrelic.ini .

ENV PORT=5000
ENV NEW_RELIC_CONFIG_FILE=/app/newrelic.ini

EXPOSE 5000

CMD ["newrelic-admin", "run-program", "python", "-m", "src.main"]