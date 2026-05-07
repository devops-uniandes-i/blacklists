FROM public.ecr.aws/docker/library/python:3.11-slim

WORKDIR /app

# Instalar curl para el healthcheck
RUN apt-get update && apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/

ENV PORT=5000

EXPOSE 5000

CMD ["python", "-m", "src.main"]