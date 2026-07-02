# VOXEL PACS DEPLOY v1.0

Infraestrutura oficial e profissional do **VOXEL PACS**, baseada na arquitetura de microserviços.

O Orthanc atua exclusivamente como repositório DICOM. Toda a inteligência (tokens, autenticação, integrações) é gerenciada pela **API VOXEL PACS** (sistema PHP 8.1 Multi-Tenant).

## Arquitetura

- ✔ **API VOXEL PACS** — PHP 8.1 MVC Multi-Tenant (código em `api/`)
- ✔ **MySQL 8.0** — banco de dados da aplicação
- ✔ **Orthanc** — servidor DICOM + DICOMweb
- ✔ **OHIF Viewer v3.12.5** — visualizador DICOM (container independente)
- ✔ **Nginx** — proxy reverso único (host)
- ✔ **Let's Encrypt SSL**
- ✔ **Storage DICOM isolado**
- ✔ **Configurações Orthanc modulares**
- ✔ **Migrations automáticas** na primeira inicialização

Para entender a arquitetura completa, leia o [ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Instalação (Zero Intervenção Manual)

```bash
# 1. Clone o repositório com submódulos
git clone --recurse-submodules \
    https://github.com/andreprogramadorbh-ai/voxelpacs-deploy.git \
    /opt/voxelpacs
cd /opt/voxelpacs

# 2. Configure as variáveis de ambiente
cp .env.example .env
nano .env

# 3. Execute o instalador
bash scripts/install.sh
```

## Variáveis Obrigatórias (`.env`)

| Variável | Descrição |
|---|---|
| `DOMAIN` | Domínio público (`view.voxelpacs.com.br`) |
| `CERTBOT_EMAIL` | E-mail para avisos de expiração do SSL |
| `ORTHANC_USERNAME` | Usuário admin do Orthanc |
| `ORTHANC_PASSWORD` | Senha admin do Orthanc |
| `DB_DATABASE` | Nome do banco MySQL |
| `DB_USERNAME` | Usuário do banco MySQL |
| `DB_PASSWORD` | Senha do banco MySQL |
| `MYSQL_ROOT_PASSWORD` | Senha root do MySQL |
| `APP_SECRET` | Chave secreta da aplicação PHP (32+ chars) |

## Scripts Oficiais

| Comando | O que faz |
|---|---|
| `bash scripts/install.sh` | Instala a plataforma do zero |
| `bash scripts/update.sh` | Atualiza sem downtime |
| `bash scripts/backup.sh` | Backup separado (banco, storage, configs) |
| `bash scripts/healthcheck.sh` | Valida saúde de todos os componentes |

## Atualizar o Código da API

```bash
# Atualizar submódulo para o commit mais recente
git submodule update --remote api
git add api && git commit -m "chore: atualiza api para commit mais recente"

# Rebuild e restart do container
cd docker && docker compose up -d --build voxelpacs-api
```

## Documentação

- [Arquitetura (ARCHITECTURE.md)](docs/ARCHITECTURE.md)
- [Instalação Detalhada (INSTALL.md)](docs/INSTALL.md)
- [API VOXEL PACS (api/README.md)](api/README.md)
- [Backup e Restore (BACKUP.md)](docs/BACKUP.md)
- [Troubleshooting (TROUBLESHOOTING.md)](docs/TROUBLESHOOTING.md)
