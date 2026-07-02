# VOXEL PACS DEPLOY v1.0

Infraestrutura oficial e profissional do **VOXEL PACS**, baseada na arquitetura de microserviços.

O Orthanc agora atua exclusivamente como repositório DICOM, enquanto toda a inteligência (tokens, autenticação, integrações) é gerenciada pela **API VOXEL PACS**.

## 🏗️ Arquitetura

- ✔ **API VOXEL PACS** (Coração do sistema)
- ✔ **PostgreSQL 16** (Índices e Metadados)
- ✔ **Orthanc** (Storage e DICOMweb)
- ✔ **OHIF Viewer v3** (Container independente)
- ✔ **Nginx** (Proxy Reverso Único)
- ✔ **Let's Encrypt SSL**
- ✔ **Storage Isolado**
- ✔ **Configurações Modulares**

Para entender a arquitetura completa, leia o [ARCHITECTURE.md](docs/ARCHITECTURE.md).

## 🚀 Instalação (Zero Intervenção Manual)

O deploy é 100% automatizado e reproduzível.

```bash
# 1. Clone o repositório no diretório base (ex: /opt/voxelpacs)
git clone https://github.com/andreprogramadorbh-ai/voxelpacs-deploy.git /opt/voxelpacs
cd /opt/voxelpacs

# 2. Configure as variáveis de ambiente
cp .env.example .env
nano .env

# 3. Execute o instalador
bash scripts/install.sh
```

## ⚙️ Variáveis Obrigatórias (`.env`)

| Variável | Descrição |
|---|---|
| `DOMAIN` | Domínio público (ex: `view.voxelpacs.com.br`) |
| `CERTBOT_EMAIL` | E-mail para avisos de expiração do SSL |
| `ORTHANC_USERNAME` | Usuário admin do Orthanc |
| `ORTHANC_PASSWORD` | Senha admin do Orthanc |
| `POSTGRES_DB` | Nome do banco de dados |
| `POSTGRES_USER` | Usuário do banco de dados |
| `POSTGRES_PASSWORD` | Senha do banco de dados |

## 🛠️ Scripts Oficiais

| Comando | O que faz |
|---|---|
| `bash scripts/install.sh` | Instala a plataforma do zero, gera SSL e sobe containers |
| `bash scripts/update.sh` | Atualiza imagens e código sem downtime |
| `bash scripts/backup.sh` | Gera backup separado (banco, storage, configs) |
| `bash scripts/healthcheck.sh`| Valida a saúde de todos os componentes (cascata) |

## 📚 Documentação

- [Arquitetura (ARCHITECTURE.md)](docs/ARCHITECTURE.md)
- [Instalação Detalhada (INSTALL.md)](docs/INSTALL.md)
- [Backup e Restore (BACKUP.md)](docs/BACKUP.md)
- [Troubleshooting (TROUBLESHOOTING.md)](docs/TROUBLESHOOTING.md)
