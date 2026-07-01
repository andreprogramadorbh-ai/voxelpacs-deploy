# VOXEL PACS — Deploy Profissional

Bem-vindo ao repositório oficial de deploy do **VOXEL PACS**.

Este repositório é responsável por instalar, atualizar e manter toda a infraestrutura do VOXEL PACS (OHIF Viewer + Nginx + SSL) de forma automatizada, reproduzível e totalmente desacoplada do Orthanc.

## 🚀 Arquitetura Desacoplada

A arquitetura foi projetada para garantir máxima flexibilidade:
- **OHIF Viewer:** Roda em containers Docker, servido por um Nginx reverso com SSL Let's Encrypt.
- **Orthanc:** Fica em outro servidor. O OHIF se conecta a ele via DICOMweb.
- **Vantagem:** Você pode migrar o Orthanc ou o OHIF para servidores diferentes sem que um afete o outro.

## 📦 Como instalar em 3 minutos

Siga estes passos em um servidor Ubuntu 24.04 limpo:

```bash
# 1. Clone o repositório
git clone https://github.com/VOXELPACS/voxelpacs-deploy.git
cd voxelpacs-deploy

# 2. Configure as variáveis de ambiente
cp .env.example .env
nano .env

# 3. Execute o instalador automático
chmod +x install.sh
./install.sh
```

Ao final da instalação, o ambiente estará disponível em: `https://view.seudominio.com.br`

## 📚 Documentação Completa

Para detalhes sobre cada operação, consulte a documentação específica na pasta `docs/`:

- [Instalação (INSTALL.md)](docs/INSTALL.md)
- [Atualização (UPDATE.md)](docs/UPDATE.md)
- [Backup e Restauração (BACKUP.md)](docs/BACKUP.md)
- [Migração de Servidor (MIGRATION.md)](docs/MIGRATION.md)
- [Certificados SSL (SSL.md)](docs/SSL.md)
- [Resolução de Problemas (TROUBLESHOOTING.md)](docs/TROUBLESHOOTING.md)

## 🛠 Scripts Disponíveis

| Script | Descrição |
|--------|-----------|
| `./install.sh` | Instala Docker, Nginx, baixa imagens e sobe os containers. |
| `./update.sh` | Atualiza as imagens Docker e o código do OHIF sem downtime. |
| `./backup.sh` | Faz backup completo de configurações, `.env` e certificados SSL. |
| `./restore.sh` | Restaura um backup previamente criado. |
| `./healthcheck.sh` | Verifica a saúde de todo o ambiente (Docker, Nginx, SSL, DNS, Orthanc). |

## 🔮 Integração Futura (Roadmap)

Esta infraestrutura está preparada para integração com:
- VOXEL B.I.
- Portal Médico e Portal do Paciente
- Inteligência Artificial (IA)
- Visualizador Mobile
- Autenticação OAuth2 / OpenID / LDAP

---
*Desenvolvido com ❤️ pela equipe VOXEL PACS.*
