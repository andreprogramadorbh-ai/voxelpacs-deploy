FROM python:3.12.11-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# UID/GID estável permite que a chave TLS permaneça root-owned no host
# e legível apenas pelo grupo do processo dentro do container (modo 0640).
RUN groupadd --system --gid 10001 voxeldicom \
    && useradd --system --uid 10001 --gid voxeldicom --home /nonexistent --shell /usr/sbin/nologin voxeldicom
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY app/gateway.py ./gateway.py
RUN mkdir -p /var/log/voxelpacs-gateway && chown -R voxeldicom:voxeldicom /var/log/voxelpacs-gateway

USER voxeldicom:voxeldicom
EXPOSE 4242 2762
HEALTHCHECK --interval=30s --timeout=3s --start-period=15s --retries=3 CMD python -c "from urllib.request import urlopen; assert urlopen('http://127.0.0.1:8081/healthz', timeout=2).status == 200"
ENTRYPOINT ["python", "/app/gateway.py", "/etc/voxelpacs-gateway/tenants.yaml"]
