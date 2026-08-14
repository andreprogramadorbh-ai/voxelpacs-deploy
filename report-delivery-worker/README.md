# VOXEL Report Delivery Hub Worker

Este worker consome jobs da outbox de laudos por uma API bearer autenticada. Ele é separado do laudário: falhas de rede, PACS, SFTP ou endpoints externos não bloqueiam o médico ao liberar um laudo.

## Estado inicial seguro

O arquivo `.env` deve começar com:

```env
DELIVERY_HUB_DRY_RUN=true
```

Neste modo, o worker registra a passagem pela fila sem enviar dados clínicos a nenhum destino. A única finalidade é validar autenticação, leasing, idempotência, reprocessamento e auditoria.

> Não definir `DELIVERY_HUB_DRY_RUN=false` nem habilitar destinos de produção antes de aplicar a migration, configurar a chave de worker no HostGator e homologar individualmente o destino do cliente.

## Instalação no VPS

```bash
sudo mkdir -p /opt/voxelpacs/report-delivery-worker
sudo rsync -a report-delivery-worker/ /opt/voxelpacs/report-delivery-worker/
sudo python3 -m venv /opt/voxelpacs/report-delivery-worker/.venv
sudo /opt/voxelpacs/report-delivery-worker/.venv/bin/pip install -r /opt/voxelpacs/report-delivery-worker/requirements.txt
sudo cp /opt/voxelpacs/report-delivery-worker/.env.example /opt/voxelpacs/report-delivery-worker/.env
sudo chmod 600 /opt/voxelpacs/report-delivery-worker/.env
sudo cp /opt/voxelpacs/report-delivery-worker/voxelpacs-report-delivery-worker.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now voxelpacs-report-delivery-worker
sudo journalctl -u voxelpacs-report-delivery-worker -f
```

## Credencial de worker

Gere uma única chave com `openssl rand -hex 32`. O mesmo valor deve existir apenas nestes dois arquivos privados:

| Local | Variável |
|---|---|
| `.env` do HostGator | `VOXEL_REPORT_DELIVERY_WORKER_TOKEN` |
| `/opt/voxelpacs/report-delivery-worker/.env` no VPS | `VOXEL_REPORT_DELIVERY_WORKER_TOKEN` |

Nunca versionar essa chave, enviá-la em e-mail, inseri-la em JSON de destino ou registrá-la em logs.

## Conectores

| Transporte | Estado do worker inicial |
|---|---|
| `https_webhook` | Implementado, mas só envia quando `DRY_RUN=false` e o destino HTTPS de homologação for explicitamente habilitado. |
| `dicom_pdf` | Contrato e fila prontos; requer gerador de Encapsulated PDF e homologação C-STORE/Storage Commitment. |
| `dicom_sr` | Contrato e fila prontos; requer mapeamento SR/TID 2000 e homologação do PACS. |
| `hl7_oru` | Contrato e fila prontos; requer profile HL7 do RIS/HIS. |
| `sftp` | Contrato e fila prontos; requer política de pasta, chave e manifesto por cliente. |

## Ativação por cliente

1. Aplicar a migration do Delivery Hub no HostGator.
2. Publicar o código PHP com `VOXEL_REPORT_DELIVERY_HUB_ENABLED=false`.
3. Configurar e iniciar o worker em `DRY_RUN=true`.
4. Cadastrar um destino em **homologação** no painel da plataforma.
5. Habilitar temporariamente a feature flag do Hub para criar um job de teste, sem dados de paciente reais quando possível.
6. Validar no painel o job, a tentativa, a idempotência e a reexecução.
7. Para HTTPS, homologar endpoint e resposta idempotente.
8. Para DICOM, validar AEs, VPN, C-STORE, associação ao estudo e Storage Commitment.
9. Para SFTP, validar chave, diretório dedicado, arquivo temporário, hash e leitura do manifesto.
10. Só após aceite clínico e técnico, liberar o destino conforme procedimento de produção aprovado.
