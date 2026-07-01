# VOXEL PACS DEPLOY

Infraestrutura oficial do VOXEL PACS.

Componentes instalados:

✔ Docker  
✔ Docker Compose  
✔ Nginx  
✔ Let's Encrypt SSL  
✔ OHIF Viewer  
✔ Proxy Reverso  
✔ Integração Orthanc  
✔ Backup Automático  
✔ Atualização Automática  

---

## Instalação

```bash
git clone https://github.com/andreprogramadorbh-ai/voxelpacs-deploy.git

cd voxelpacs-deploy

cp .env.example .env

nano .env

bash install.sh
```

---

## Configuração (.env)

Antes de executar a instalação, configure o arquivo `.env` com os dados do seu ambiente:

| Variável | Descrição | Exemplo |
|---|---|---|
| `DOMAIN` | Domínio que aponta para este servidor | `view.voxelpacs.com.br` |
| `CERTBOT_EMAIL` | E-mail para notificações SSL | `andre@voxelpacs.com.br` |
| `GENERATE_SSL` | Gerar certificado SSL automaticamente | `yes` |
| `OHIF_NAME` | Nome exibido no OHIF Viewer | `VOXEL PACS` |
| `OHIF_PORT` | Porta interna do OHIF | `3000` |
| `ORTHANC_PROTOCOL` | Protocolo de conexão com o Orthanc | `http` |
| `ORTHANC_HOST` | IP ou domínio do servidor Orthanc | `46.225.51.122` |
| `ORTHANC_PORT` | Porta HTTP do Orthanc | `8042` |
| `ORTHANC_USERNAME` | Usuário do Orthanc | `vivere_admin` |
| `ORTHANC_PASSWORD` | Senha do Orthanc | `SuaSenha` |
| `ORTHANC_AET` | AE Title do Orthanc | `ORTHANCPACS` |
| `TIMEZONE` | Fuso horário do servidor | `America/Sao_Paulo` |
| `BACKUP_DIR` | Diretório de backups | `./backups` |

---

## Scripts disponíveis

| Script | Descrição |
|---|---|
| `bash install.sh` | Instala todo o ambiente do zero |
| `bash update.sh` | Atualiza imagens Docker sem downtime |
| `bash backup.sh` | Gera backup de configurações e certificados SSL |
| `bash restore.sh <arquivo>` | Restaura um backup previamente criado |
| `bash healthcheck.sh` | Verifica a saúde de todo o ambiente |

---

## Documentação

- [Instalação detalhada](docs/INSTALL.md)
- [Atualização](docs/UPDATE.md)
- [Backup e Restauração](docs/BACKUP.md)
- [Migração de Servidor](docs/MIGRATION.md)
- [Certificados SSL](docs/SSL.md)
- [Resolução de Problemas](docs/TROUBLESHOOTING.md)

---

## Arquitetura

```
Internet
    │
    ▼
[ Nginx + SSL ]  ← Let's Encrypt (porta 443)
    │
    ▼
[ OHIF Viewer ]  ← Container Docker (porta 3000)
    │
    ▼
[ Orthanc PACS ]  ← Servidor remoto (DICOMweb)
```

O Nginx atua como proxy reverso, terminando o SSL e encaminhando as requisições DICOMweb para o Orthanc remoto, evitando problemas de CORS no navegador.

---

*Desenvolvido pela equipe VOXEL PACS.*
