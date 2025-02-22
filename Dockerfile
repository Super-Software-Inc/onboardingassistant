# syntax=docker/dockerfile:1

# Initialize build arguments
ARG USE_CUDA=false
ARG USE_OLLAMA=false
ARG USE_CUDA_VER=cu121  # CUDA 12 default
ARG USE_EMBEDDING_MODEL=sentence-transformers/all-MiniLM-L6-v2
ARG USE_RERANKING_MODEL=""
ARG USE_TIKTOKEN_ENCODING_NAME="cl100k_base"
ARG BUILD_HASH=dev-build
ARG UID=0
ARG GID=0

######## WebUI Frontend ########
FROM --platform=$BUILDPLATFORM node:22-alpine3.20 AS build
ARG BUILD_HASH
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
ENV APP_BUILD_HASH=${BUILD_HASH}
RUN npm run build

######## WebUI Backend ########
FROM python:3.11-slim-bookworm AS base
ARG USE_CUDA
ARG USE_OLLAMA
ARG USE_CUDA_VER
ARG USE_EMBEDDING_MODEL
ARG USE_RERANKING_MODEL
ARG UID
ARG GID

# Set environment variables explicitly
ARG OPENAI_API_KEY
ARG ASSISTANT_ID
ENV ENV=prod \
    PORT=3000 \
    WEBSERVER_PORT=3000 \
    USE_OLLAMA_DOCKER=${USE_OLLAMA} \
    USE_CUDA_DOCKER=${USE_CUDA} \
    USE_CUDA_DOCKER_VER=${USE_CUDA_VER} \
    USE_EMBEDDING_MODEL_DOCKER=${USE_EMBEDDING_MODEL} \
    USE_RERANKING_MODEL_DOCKER=${USE_RERANKING_MODEL} \
    OPENAI_API_KEY=${OPENAI_API_KEY} \
    ASSISTANT_ID=${ASSISTANT_ID} \
    ENABLE_WEB_SEARCH=true \
    SCARF_NO_ANALYTICS=true \
    DO_NOT_TRACK=true \
    ANONYMIZED_TELEMETRY=false

## Basis URL Config ##
ENV OLLAMA_BASE_URL="/ollama" \
    OPENAI_API_BASE_URL=""

# Ensure correct user permissions
WORKDIR /app/backend
ENV HOME=/root

# Create user and group if not root
RUN if [ $UID -ne 0 ]; then \
    if [ $GID -ne 0 ]; then \
    addgroup --gid $GID app; \
    fi; \
    adduser --uid $UID --gid $GID --home $HOME --disabled-password --no-create-home app; \
    fi

# Create cache storage for embeddings, OCR, and telemetry
RUN mkdir -p $HOME/.cache/chroma
RUN echo -n 00000000-0000-0000-0000-000000000000 > $HOME/.cache/chroma/telemetry_user_id
RUN chown -R $UID:$GID /app $HOME

# Install required dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git build-essential pandoc gcc netcat-openbsd curl jq \
    gcc python3-dev ffmpeg libsm6 libxext6 libgl1 && \
    rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY --chown=$UID:$GID ./backend/requirements.txt ./requirements.txt
RUN pip3 install uv && \
    pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu --no-cache-dir && \
    uv pip install --system -r requirements.txt --no-cache-dir

# Copy built frontend files
COPY --chown=$UID:$GID --from=build /app/build /app/build
COPY --chown=$UID:$GID --from=build /app/CHANGELOG.md /app/CHANGELOG.md
COPY --chown=$UID:$GID --from=build /app/package.json /app/package.json

# Copy backend files
COPY --chown=$UID:$GID ./backend .

# Expose the correct Open WebUI port
EXPOSE 3000

# Healthcheck for Render
HEALTHCHECK CMD curl --silent --fail http://localhost:${PORT:-3000}/health | jq -ne 'input.status == true' || exit 1

# Ensure correct user permissions
USER $UID:$GID

ARG BUILD_HASH
ENV WEBUI_BUILD_VERSION=${BUILD_HASH}
ENV DOCKER=true

# Start Open WebUI
CMD ["bash", "start.sh"]
