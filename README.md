# VOXEL PACS DEPLOY

Infraestrutura oficial de deploy profissional do **VOXEL PACS**.

Este repositório automatiza a instalação, configuração e manutenção do ambiente PACS, compatível com Ubuntu 24.04 e versões V1 e V2 do Docker Compose.

### Componentes instalados:

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

## Instalação em 1 minuto

O deploy foi projetado para funcionar **sem necessidade de editar nenhum arquivo de código ou configuração manualmente**. Tudo é gerado a partir do `.env`.

Execute em um servidor Ubuntu limpo:

```bash
git clone https://github.com/andreprogramadorbh-ai/voxelpacs-deploy.git

cd voxelpacs-deploy

cp .env.example .env

nano .env

bash install.sh
```

---

## Configuração (.env)

Antes de rodar o `install.sh`, você deve preencher o arquivo `.env`. As seguintes variáveis são obrigatórias:

| Variável | Descrição | Exemplo |
|---|---|---|
| `DOMAIN` | Domínio apontado para o servidor | `view.voxelpacs.com.br` |
| `CERTBOT_EMAIL` | E-mail para renovação do SSL | `andre@voxelpacs.com.br` |
| `ORTHANC_HOST` | IP/Domínio do servidor Orthanc | `46.225.51.122` |
| `ORTHANC_PORT` | Porta HTTP do Orthanc | `8042` |
| `ORTHANC_USERNAME` | Usuário do Orthanc | `vivere_admin` |
| `ORTHANC_PASSWORD` | Senha do Orthanc | `SuaSenhaForte` |

Outras variáveis opcionais (com valores padrão) já vêm configuradas no `.env.example`.

---

## Scripts Disponíveis

Todos os scripts detectam automaticamente o seu sistema operacional e a versão do Docker Compose instalada.

| Comando | O que faz? |
|---|---|
| `bash install.sh` | Instala Docker, Nginx, OHIF, gera configurações e sobe o ambiente. |
| `bash deploy.sh` | Alias para `install.sh`. |
| `bash update.sh` | Atualiza o código via Git, baixa novas imagens e reinicia sem downtime. |
| `bash rollback.sh` | Reverte o código para o commit anterior e reinicia os containers. |
| `bash healthcheck.sh` | Valida Docker, containers, Nginx, OHIF, Orthanc, DICOMweb e validade do SSL. |
| `bash backup.sh` | Gera um arquivo compactado com as configurações, `.env` e certificados. |
| `bash restore.sh <arquivo>`| Restaura um backup gerado anteriormente. |

---

## Arquitetura

O sistema utiliza o Nginx como proxy reverso para evitar problemas de CORS no navegador ao se comunicar com o Orthanc remoto.

```
Internet (Navegador do Médico)
    │
    ▼
[ Nginx + SSL Let's Encrypt ]  ← Porta 443
    │
    ├──► /           → [ OHIF Viewer ] (Container Docker - Porta 3000)
    │
    └──► /dicom-web/ → [ Orthanc PACS ] (Servidor Remoto via DICOMweb)
```

O arquivo `app-config.js` do OHIF e as configurações do Nginx são **gerados dinamicamente** pelo `install.sh` com base nas variáveis do `.env`, eliminando a necessidade de configurar IPs fixos manualmente.

---

## Documentação Completa

Para cenários avançados, consulte a documentação detalhada na pasta `docs/`:

- [Instalação Detalhada](docs/INSTALL.md)
- [Atualização (Update)](docs/UPDATE.md)
- [Backup e Restauração](docs/BACKUP.md)
- [Migração de Servidor](docs/MIGRATION.md)
- [Gerenciamento de SSL](docs/SSL.md)
- [Resolução de Problemas (Troubleshooting)](docs/TROUBLESHOOTING.md)

---
*Desenvolvido pela equipe VOXEL PACS.*
