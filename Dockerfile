# syntax=docker/dockerfile:1.7

# Simplified Dockerfile for litellm proxy deployment
# Skips UI build to reduce image size

ARG LITELLM_BUILD_IMAGE=cgr.dev/chainguard/wolfi-base@sha256:e624c5d5e42382ce7165ddafcbbf8e6769a24cbd02ea6114b880b05ae5ba2a8d
ARG LITELLM_RUNTIME_IMAGE=cgr.dev/chainguard/wolfi-base@sha256:e624c5d5e42382ce7165ddafcbbf8e6769a24cbd02ea6114b880b05ae5ba2a8d
ARG UV_IMAGE=ghcr.io/astral-sh/uv:0.11.7@sha256:240fb85ab0f263ef12f492d8476aa3a2e4e1e333f7d67fbdd923d00a506a516a

FROM $UV_IMAGE AS uvbin

# Builder stage
FROM $LITELLM_BUILD_IMAGE AS builder

WORKDIR /app
USER root

COPY --from=uvbin /uv /usr/local/bin/uv
COPY --from=uvbin /uvx /usr/local/bin/uvx

RUN apk add --no-cache \
    bash \
    gcc \
    python-3.13 \
    python-3.13-dev \
    rust \
    openssl \
    openssl-dev \
    nodejs \
    npm \
    libsndfile

ENV UV_PROJECT_ENVIRONMENT=/app/.venv \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=0 \
    PATH="/app/.venv/bin:${PATH}"

# Create minimal pyproject.toml for installation
RUN mkdir -p enterprise litellm-proxy-extras

# Create minimal pyproject.toml files using printf
RUN printf '[project]\nname = "litellm-enterprise"\nversion = "0.1.0"\nrequires-python = ">=3.11"\ndependencies = []\n' > enterprise/pyproject.toml

RUN printf '[project]\nname = "litellm-proxy-extras"\nversion = "0.1.0"\nrequires-python = ">=3.11"\ndependencies = []\n' > litellm-proxy-extras/pyproject.toml

# Create minimal uv.lock using printf
RUN printf '[[package]]\nname = "litellm"\nversion = "0.0.0"\nsource = { editable = "." }\ndependencies = []\n\n[package.metadata]\nrequires-python = ">=3.11"\n' > uv.lock

# Copy source
COPY . .

# Build and install
RUN uv sync --no-default-groups --no-editable \
    --extra proxy \
    --extra proxy-runtime \
    --python python3.13 || true

# Runtime stage
FROM $LITELLM_RUNTIME_IMAGE AS runtime

USER root

RUN echo "https://packages.wolfi.dev/os" >> /etc/apk/repositories
RUN apk add --no-cache bash openssl tzdata nodejs python-3.13 libsndfile

WORKDIR /app
ENV PATH="/app/.venv/bin:${PATH}"

# Copy application files
COPY --from=builder /app/litellm /app/litellm
COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/pyproject.toml /app/pyproject.toml

# Create entrypoint
RUN printf '#!/bin/bash\nexec python -m litellm.proxy.proxy_cli --port ${PORT:-4000}\n' > /app/entrypoint.sh && \
    chmod +x /app/entrypoint.sh

EXPOSE 4000/tcp

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["--port", "4000"]
