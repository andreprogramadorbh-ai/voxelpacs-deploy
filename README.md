# VOXEL PACS DEPLOY

Infraestrutura oficial e limpa do VOXEL PACS (v1.0).

## Componentes

✔ **Docker** — Containers independentes com versões fixas
✔ **Nginx** — Reverse Proxy com VirtualHosts separados e HTTPS
✔ **Orthanc** — Servidor DICOM modular com 10 plugins
✔ **OHIF Viewer** — Versão v3.12.5 com configuração dataSources
✔ **PostgreSQL** — Banco de dados relacional
✔ **Storage** — Armazenamento DICOM persistente

## Domínios

* **Viewer:** `https://view.voxelpacs.com.br`
* **DICOM:** `https://dicom.voxelpacs.com.br`

## Estrutura do Servidor (`/opt/voxelpacs`)

```
/opt/voxelpacs/
├── docker/         # docker-compose.yml
├── nginx/          # VirtualHosts (view.conf, dicom.conf)
├── ohif/           # app-config.js (OHIF v3) e logo
├── orthanc/        # Configurações JSON modulares
├── postgres/       # Banco de dados
├── storage/dicom/  # Arquivos DICOM (.dcm)
├── backups/        # Backups automatizados
├── logs/           # Logs do Nginx
└── scripts/        # Automação (install, healthcheck, backup)
```

## Instalação

```bash
git clone https://github.com/andreprogramadorbh-ai/voxelpacs-deploy.git /opt/voxelpacs
cd /opt/voxelpacs
bash scripts/install.sh
```

## Healthcheck

```bash
bash scripts/healthcheck.sh
```
