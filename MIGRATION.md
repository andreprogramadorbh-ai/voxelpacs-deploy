# VOXEL PACS — Guia de Migração: SQLite → PostgreSQL (Fase 2)

## Visão Geral

A **Fase 2** do VOXEL PACS introduz o **PostgreSQL 16** como banco de dados para o índice DICOM do Orthanc, substituindo o SQLite embutido. Esta migração melhora a performance, escalabilidade e confiabilidade do sistema em ambientes de produção com alto volume de exames.

| Componente | Antes (SQLite) | Depois (PostgreSQL) |
|---|---|---|
| Índice DICOM | `storage/dicom/orthanc.db` | Container `voxelpacs-postgres-orthanc` |
| Storage DICOM | `storage/dicom/*.dcm` | `storage/dicom/*.dcm` (sem mudança) |
| Banco API PHP | MySQL 8.0 | MySQL 8.0 (sem mudança) |
| Container extra | — | `voxelpacs-postgres-orthanc` (postgres:16) |

> **Importante:** Os arquivos DICOM binários (`.dcm`) **não são movidos** — apenas o índice de metadados muda de SQLite para PostgreSQL. O `EnableStorage: false` no `postgresql.json` garante isso.

---

## Arquitetura dos Bancos de Dados

O VOXEL PACS usa **dois bancos separados** com propósitos distintos:

```
┌─────────────────────────────────────────────────────────┐
│  voxelpacs-mysql (MySQL 8.0)                            │
│  Banco: voxel_pacs                                      │
│  Uso: dados da API PHP (usuários, tokens, auditoria)    │
│  Porta: interna Docker apenas                           │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  voxelpacs-postgres-orthanc (PostgreSQL 16)             │
│  Banco: orthanc_voxel                                   │
│  Uso: índice DICOM do Orthanc (UIDs, hierarquia, tags)  │
│  Porta: interna Docker apenas (sem exposição externa)   │
└─────────────────────────────────────────────────────────┘
```

---

## Pré-requisitos

Antes de executar a migração, verifique:

1. **`.env` configurado** com `POSTGRES_ORTHANC_PASSWORD`:
   ```bash
   grep POSTGRES_ORTHANC_PASSWORD .env
   # Deve retornar: POSTGRES_ORTHANC_PASSWORD=<senha_forte>
   ```

2. **`orthanc/postgresql.json` com senha substituída** (feito pelo `install.sh`):
   ```bash
   grep -v "PLACEHOLDER" orthanc/postgresql.json | grep -q "Password"
   echo $?  # Deve retornar 0
   ```

3. **Storage DICOM acessível**:
   ```bash
   ls -la storage/dicom/ | head -5
   ```

4. **Docker e containers funcionando**:
   ```bash
   docker ps | grep voxelpacs
   ```

---

## Executando a Migração

### Opção 1: Script automatizado (recomendado)

```bash
# Dry-run primeiro (apenas valida, sem alterações)
sudo bash scripts/migrate-sqlite-to-postgres.sh --dry-run

# Migração real
sudo bash scripts/migrate-sqlite-to-postgres.sh
```

### Opção 2: Migração manual passo a passo

```bash
# 1. Backup do SQLite
cp storage/dicom/orthanc.db backups/orthanc_pre_migration_$(date +%Y%m%d).db

# 2. Parar o Orthanc
cd docker && docker compose stop orthanc && cd ..

# 3. Subir o PostgreSQL Orthanc
cd docker && docker compose up -d postgres-orthanc && cd ..

# 4. Aguardar PostgreSQL estar pronto
docker exec voxelpacs-postgres-orthanc pg_isready -U orthanc_user -d orthanc_voxel

# 5. Reiniciar Orthanc (reindexará automaticamente)
cd docker && docker compose up -d orthanc && cd ..

# 6. Monitorar reindexação
docker logs -f voxelpacs-orthanc

# 7. Validar
curl -sf -u "$ORTHANC_USERNAME:$ORTHANC_PASSWORD" http://localhost:8042/statistics
```

---

## Como o Orthanc Reindexar Funciona

Quando o Orthanc inicia com `EnableIndex: true` no `postgresql.json`:

1. Detecta que o banco PostgreSQL está vazio (sem tabelas ou tabelas vazias)
2. Varre todos os arquivos no `StorageDirectory` (`/var/lib/orthanc/db`)
3. Reconstrói o índice completo no PostgreSQL automaticamente
4. Após a reindexação, todos os estudos ficam disponíveis via DICOMweb

> **Não existe migração direta SQLite → PostgreSQL** no Orthanc. O índice é sempre reconstruído a partir dos arquivos DICOM no storage.

---

## Monitoramento Durante a Migração

```bash
# Acompanhar logs do Orthanc em tempo real
docker logs -f voxelpacs-orthanc

# Verificar progresso de reindexação
curl -sf -u "$ORTHANC_USERNAME:$ORTHANC_PASSWORD" \
  http://localhost:8042/statistics | python3 -m json.tool

# Verificar tabelas no PostgreSQL
docker exec voxelpacs-postgres-orthanc \
  psql -U orthanc_user -d orthanc_voxel \
  -c "SELECT schemaname, tablename, n_live_tup FROM pg_stat_user_tables ORDER BY n_live_tup DESC;"

# Healthcheck completo
bash scripts/healthcheck.sh
```

---

## Tempo Estimado

| Volume de Estudos | Tempo Estimado |
|---|---|
| < 100 estudos | 1-2 minutos |
| 100-1.000 estudos | 5-10 minutos |
| 1.000-10.000 estudos | 30-60 minutos |
| > 10.000 estudos | 1-3 horas |

O tempo varia conforme o hardware do servidor e o tamanho médio dos estudos.

---

## Rollback

Se a migração falhar ou o sistema apresentar problemas após a migração:

```bash
# 1. Parar o Orthanc
cd docker && docker compose stop orthanc && cd ..

# 2. Restaurar o SQLite original
cp backups/<timestamp>/sqlite/orthanc_pre_migration_<timestamp>.db \
   storage/dicom/orthanc.db

# 3. Remover o postgresql.json do container (ou comentar EnableIndex)
# Editar orthanc/postgresql.json e definir "EnableIndex": false

# 4. Reiniciar o Orthanc
cd docker && docker compose up -d orthanc && cd ..

# 5. Verificar
curl -sf -u "$ORTHANC_USERNAME:$ORTHANC_PASSWORD" http://localhost:8042/system
```

---

## Backup Pós-Migração

Após a migração, o backup do banco muda de SQLite para PostgreSQL:

```bash
# Backup completo (PostgreSQL Orthanc + MySQL API + Storage + Configs)
bash scripts/backup.sh

# Backup apenas dos bancos
bash scripts/backup.sh --db

# Backup manual do PostgreSQL Orthanc
docker exec voxelpacs-postgres-orthanc pg_dump \
  -U orthanc_user -d orthanc_voxel \
  --format=custom --compress=9 \
  > backups/orthanc_index_$(date +%Y%m%d).dump

# Restaurar backup PostgreSQL Orthanc
docker exec -i voxelpacs-postgres-orthanc pg_restore \
  -U orthanc_user -d orthanc_voxel \
  < backups/orthanc_index_<timestamp>.dump
```

---

## Configuração do PostgreSQL Orthanc

O arquivo `orthanc/postgresql.json` controla a integração:

```json
{
  "PostgreSQL": {
    "Host": "postgres-orthanc",
    "Port": 5432,
    "Database": "orthanc_voxel",
    "Username": "orthanc_user",
    "Password": "<gerado pelo install.sh>",
    "EnableIndex": true,
    "EnableStorage": false,
    "Lock": true,
    "IndexConnectionsCount": 20,
    "TransactionMode": "ReadCommitted",
    "UseDynamicConnectionPool": true
  }
}
```

| Parâmetro | Valor | Motivo |
|---|---|---|
| `EnableIndex` | `true` | Índice de metadados no PostgreSQL |
| `EnableStorage` | `false` | Arquivos DICOM no filesystem (mais eficiente) |
| `Lock` | `true` | Apenas 1 instância Orthanc (Fase 3: alterar para `false`) |
| `IndexConnectionsCount` | `20` | Pool de conexões para workloads simultâneos |

---

## Fase 3 (Futura): Alta Disponibilidade

Quando o sistema evoluir para múltiplas instâncias Orthanc:

1. Alterar `Lock: false` no `postgresql.json`
2. Configurar `DicomCheckCalledAet: true` e `DicomCheckCallingAet: true` no `orthanc.json`
3. Cadastrar todos os modalities em `DicomModalities`
4. Configurar load balancer para as instâncias Orthanc

---

## Referências

- [Orthanc PostgreSQL Plugin](https://orthanc.uclouvain.be/book/plugins/postgresql.html)
- [Orthanc Storage Plugins](https://orthanc.uclouvain.be/book/plugins/storage-plugins.html)
- [OHIF Viewer DICOMweb](https://docs.ohif.org/configuration/dataSources/dicom-web)
