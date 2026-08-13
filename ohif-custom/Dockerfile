# syntax=docker/dockerfile:1
# VOXEL VIEW — OHIF v3.12.5 com extensão de integração de medições.
# A fonte upstream é fixada por tag para preservar compatibilidade de API.
FROM node:20.18.1-slim AS builder

ARG OHIF_GIT_REF=v3.12.5
WORKDIR /usr/src

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential ca-certificates git python3 \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g bun@1.2.23 lerna@7.4.2

RUN git clone --depth 1 --branch "${OHIF_GIT_REF}" https://github.com/OHIF/Viewers.git ohif
WORKDIR /usr/src/ohif

# Apenas a configuração de plugins e a extensão VOXEL sobrescrevem a tag oficial.
COPY pluginConfig.json /usr/src/ohif/platform/app/pluginConfig.json
COPY extensions/voxel-measurement-adapter /usr/src/ohif/extensions/voxel-measurement-adapter

RUN bun pm cache rm \
    && bun install \
    && bun add ajv@8.12.0

ENV QUICK_BUILD=true
ENV APP_CONFIG=config/default.js
RUN bun run build

# Mantém o entrypoint e a configuração Nginx oficiais da imagem OHIF estável.
FROM ohif/app:v3.12.5
USER root
COPY --from=builder /usr/src/ohif/platform/app/dist /usr/share/nginx/html
RUN chown -R nginx:nginx /usr/share/nginx/html && chmod -R 755 /usr/share/nginx/html
USER nginx
