# Gateway DICOM — Cliente A

Este pacote implementa a borda DICOM da célula canária. Ele aceita somente `C-ECHO` e `C-STORE`; roteia por Called AE; valida IP, Calling AE e serviço por tenant; e registra metadados de associação sem tags clínicas. Não armazena arquivos DICOM.

## Identidades reservadas

| Papel | Valor |
|---|---|
| Called AE público do gateway A | `VOXEL_GW_A` |
| Calling AE interno do gateway A | `VOXEL_GW_A` |
| Called AE do Orthanc A | `VOXEL_A_PACS` |
| Rede privada Hetzner | `10.0.0.0/16` |
| Gateway reservado | `10.0.0.10` |
| Orthanc A reservado | `10.0.10.10` |
| IP VPN reservado ao emissor A | `10.200.10.2` |

## Ordem de implantação

1. Criar `gateway-dicom-01` em Nuremberg, com IPv4 público, rede privada `voxel-private-eu-central`, firewall dedicado e uma chave SSH autorizada.
2. Criar `tenant-a-pacs-01` em Nuremberg, somente com rede privada, firewall dedicado, sem IPv4/IPv6 públicos e um volume DICOM independente.
3. Copiar este diretório para `/opt/voxelpacs/gateway` no gateway, executar `bootstrap-gateway.sh` e instalar os arquivos root-only em `/etc/voxelpacs-gateway`.
4. Gerar a chave privada WireGuard localmente no gateway: `umask 077; wg genkey | tee /etc/wireguard/gateway.key | wg pubkey > /etc/wireguard/gateway.pub`.
5. Inserir a chave pública fornecida pelo Cliente A no `wg0.conf`; o peer permanece desabilitado até o teste de conectividade VPN.
6. Copiar `tenants.example.yaml` para `tenants.yaml`, substituir somente valores operacionais aprovados e manter `enabled: false` até a homologação.
7. Copiar a célula A para sua VM, gerar credenciais únicas no host, subir Orthanc e validar que ele não é alcançável da Internet.
8. Após C-ECHO pela VPN, habilitar `cliente-a` no gateway e testar C-STORE exclusivamente com DICOM sintético.

## Rotação e reversão

A remoção de um peer é feita apagando o bloco correspondente de `/etc/wireguard/wg0.conf` e aplicando `wg syncconf wg0 <(wg-quick strip wg0)`. A desativação imediata da rota é feita alterando `enabled: false` para o tenant e executando `systemctl restart voxelpacs-dicom-gateway`. Ambas as operações não removem qualquer objeto de Orthanc.

A chave de WireGuard é exclusiva por emissor. Uma chave comprometida deve ser revogada, substituída e associada a novo IP `/32`; nunca reutilize uma chave entre clientes.
