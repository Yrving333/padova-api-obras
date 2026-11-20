# ---------- Etapa 1: builder (instala dependencias en un entorno aislado) ----------
FROM python:3.12-slim AS builder

WORKDIR /build
COPY requirements.txt .
RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

# ---------- Etapa 2: runtime (solo lo necesario para ejecutar) ----------
FROM python:3.12-slim

# Trazabilidad: el script de despliegue pasa rama-commit como version
ARG APP_VERSION=dev
LABEL org.opencontainers.image.title="api-obras" \
      org.opencontainers.image.description="Microservicio de proyectos inmobiliarios - Grupo Padova" \
      org.opencontainers.image.version="${APP_VERSION}"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:${PATH}" \
    PORT=8080 \
    APP_VERSION=${APP_VERSION}

# Dependencias ya instaladas, traidas de la etapa builder (sin pip ni cache en la imagen final)
COPY --from=builder /opt/venv /opt/venv

WORKDIR /app
# COPY selectivo: solo el codigo de la app (no "COPY . .")
COPY app/ ./app/

# Usuario sin privilegios
RUN useradd --create-home --uid 10001 appuser
USER appuser

# Debe coincidir con target_port del ingress en Terraform
EXPOSE 8080

# Healthcheck para "docker run" local. En Azure Container Apps lo cubren los probes de Terraform.
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=4).status == 200 else 1)"

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT}"]
