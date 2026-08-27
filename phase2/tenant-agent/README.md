# Agente operacional de células DICOM tenant

O agente executa operações restritas e idempotentes nos hosts existentes do VOXEL PACS. Ele não cria VMs, discos, IPs públicos, buckets ou qualquer recurso pago. A API não recebe privilégios de root: ela assina uma ordem de curta duração e o agente valida origem, assinatura, nonce, payload e função do host antes de executar.

## Perfis de host

| Perfil | Host | Ações permitidas |
|---|---|---|
| `hybrid` | Host das células Orthanc/PostgreSQL | `provision_cell` |
| `gateway` | Gateway DICOM compartilhado | `configure_wireguard_echo`, `check_echo`, `enable_cstore`, `suspend_route` |

O perfil é obrigatório. Um agente `hybrid` não manipula WireGuard ou a política do gateway, e um agente `gateway` não cria containers ou diretórios de dados.

## Segurança do transporte

O serviço aceita somente a origem privada da API, configurada em `API_SOURCE_IP`. Cada chamada `POST /v1/operations` exige `X-Voxel-Timestamp`, `X-Voxel-Nonce` e `X-Voxel-Signature`; a assinatura é HMAC-SHA256 sobre `timestamp.nonce.body`. Ordens expiram em dois minutos e o nonce é gravado uma única vez em diretório root-only.

A chave HMAC deve existir somente em arquivos `0600` do usuário root: uma cópia em cada agente e uma cópia na API. Nunca a grave no repositório, `.env` versionado, browser, PDF de integração, auditoria ou ticket.

## Instalação

Copie este diretório para o host alvo e execute como root:

```bash
./install-agent.sh --role hybrid --bind-host 10.0.0.3 --api-source-ip 10.0.0.2 --hmac-key-file /caminho/root-only/hmac.key
```

No gateway, substitua o perfil e endereço privado correspondentes. O instalador cria `/etc/voxelpacs-tenant-agent/agent.env`, instala o script em `/usr/local/lib/voxelpacs/tenant-agent`, registra a unidade systemd e abre a porta configurada apenas para o IP privado da API.

## Operação de uma célula VPN-only

1. A interface reserva slug, AEs, portas privadas e IP VPN sem alteração de infraestrutura.
2. Após confirmação, a API solicita ao agente híbrido a criação da célula Orthanc/PostgreSQL/storage e do contrato de backup desabilitado.
3. A API solicita ao gateway a criação do peer WireGuard e da rota que aceita somente C-ECHO.
4. O sistema gera o PDF sem chave privada; o cliente instala a configuração local e executa C-ECHO.
5. A interface verifica somente a auditoria técnica. A liberação de C-STORE exige confirmação posterior e separada.
6. Backup clínico, retenção, restore, rotação de peer e remoção de dados também continuam sujeitos a confirmação específica.

## Diagnóstico

- Saúde local: `curl --fail http://IP_PRIVADO:8813/healthz` executado exclusivamente a partir da API privada.
- Journal: `journalctl -u voxelpacs-tenant-agent --since '1 hour ago'`.
- Auditoria segura: `/var/log/voxelpacs/tenant-agent.jsonl` contém apenas identificador de operação, tenant, etapa e código técnico; não contém PHI, UIDs ou segredos.

## Rotação

A rotação exige manutenção coordenada e aprovação: gere a nova chave em arquivo root-only, instale nos dois agentes e na API, recarregue as unidades e faça uma chamada de saúde. Não rotacione durante uma ordem em andamento. O segredo anterior só pode ser removido após validar a nova assinatura em ambos os agentes.
