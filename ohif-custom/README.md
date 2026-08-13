# VOXEL VIEW — imagem OHIF com adapter de medições

Este diretório cria uma imagem reproduzível do **OHIF Viewer v3.12.5** com a extensão privada `@voxel/extension-measurement-adapter`.

> A imagem não altera os mappers nem o `MeasurementService` do OHIF. Ela somente assina os eventos de medição e envia snapshots normalizados ao endpoint HTTPS do VOXEL PACS.

## Artefatos

| Caminho | Finalidade |
|---|---|
| `Dockerfile` | Compila o upstream `OHIF/Viewers` na tag fixa `v3.12.5`. |
| `pluginConfig.json` | Registra `@voxel/extension-measurement-adapter` como extensão default. |
| `extensions/voxel-measurement-adapter/` | Serviço que observa add/update/remove/clear do `MeasurementService`. |

## Pré-requisitos para ativação

A ordem é obrigatória:

1. Publicar no HostGator o backend do commit da integração.
2. Aplicar `2026-08-13_voxel_measurement_integration.sql` pelo phpMyAdmin, após backup.
3. Verificar a disponibilidade do endpoint `OPTIONS /api/viewer/measurements` com origin `https://view.voxelpacs.com.br`.
4. No VPS, atualizar o repositório e construir a imagem.
5. Reiniciar apenas o container `voxelpacs-ohif`.
6. Abrir um estudo por `/estudos/{id}/abrir`, realizar uma medida e confirmar o painel do laudário.

## Build e rollout no VPS

```bash
cd /opt/voxelpacs/deploy/docker
sudo docker compose build --no-cache ohif
sudo docker compose up -d --no-deps ohif
sudo docker ps --filter name=voxelpacs-ohif
```

O primeiro build baixa e compila o OHIF, portanto é significativamente mais lento que um restart comum. Não execute durante uso clínico intenso. O `app-config.js` continua montado como volume e define o endpoint do backend; não contém token, senha ou segredo.

## Verificação funcional

| Verificação | Resultado esperado |
|---|---|
| URL aberta pelo fluxo seguro | Fragmento temporário `#voxel_measurement_token=...`, removido da barra logo após a inicialização. |
| Medição no VOXEL VIEW | `POST /api/viewer/measurements` autenticado por bearer token curto. |
| Laudário do mesmo estudo | A medida aparece em **Medidas disponíveis do viewer** em até 15 segundos ou após clicar em atualizar. |
| Inserção no laudo | O backend cria snapshot de versão e `report_measurement_usages` em transação. |
| Acesso de origin não autorizado | Preflight CORS sem `Access-Control-Allow-Origin`; browser bloqueia a chamada. |

## Rollback da imagem do viewer

Se o adapter precisar ser desativado antes de uma correção, restaure temporariamente a imagem anterior no `docker-compose.yml`:

```yaml
image: ohif/app:v3.12.5
```

Remova o bloco `build:` do serviço `ohif` e execute `sudo docker compose up -d --no-deps ohif`. O backend e as tabelas de snapshots podem permanecer; a interrupção da sincronização não altera as medições já inseridas em laudos.
