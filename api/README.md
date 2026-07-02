# API VOXEL PACS

Este diretório contém a configuração e integração da **API VOXEL PACS** no ambiente de deploy.

## Responsabilidades

A API VOXEL PACS é o coração do sistema. Ela é responsável por:

| Funcionalidade | Descrição |
|---|---|
| **Autenticação** | Login, sessões, JWT |
| **RBAC** | Controle de acesso por papel (médico, técnico, admin) |
| **Tokens de acesso** | Geração de tokens temporários para abertura de exames |
| **Auditoria** | Log de todos os acessos e ações |
| **Integração RIS** | Recebimento de worklists e resultados |
| **Integração ERP** | Sincronização com o sistema de gestão (inlaudo) |
| **Integração HL7** | Mensagens HL7 v2/FHIR |
| **Compartilhamento** | Links temporários para compartilhar exames |
| **IA** | Integração com modelos de análise de imagens |

## Fluxo de abertura de exame

```
ERP (inlaudo)
    │
    ▼ POST /api/tokens
API VOXEL PACS
    │
    ▼ Valida permissão + gera token
Token (UUID)
    │
    ▼ GET /open/{token}
Nginx → API
    │
    ▼ Resolve token → StudyInstanceUID
    │
    ▼ 302 Redirect
OHIF Viewer (/viewer?StudyInstanceUIDs=...)
```

## Endpoints de monitoramento

| Endpoint | Descrição |
|---|---|
| `GET /api/health` | Status da API |
| `GET /api/ready` | Verifica PostgreSQL + Orthanc + DICOMweb |
| `GET /api/live` | Liveness probe |

## Container Docker

O container `voxelpacs-api` é definido em `docker/docker-compose.yml`.

A imagem padrão é um placeholder — substitua pela imagem real da API quando disponível:

```yaml
voxelpacs-api:
  image: ghcr.io/andreprogramadorbh-ai/voxelpacs-api:latest
```

## Variáveis de ambiente

Ver `.env.example` — seção `API VOXEL PACS`.
