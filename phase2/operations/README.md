# Operação segregada por tenant

Este diretório contém ativos para backup, restauração e saúde técnica de células híbridas. Nenhum script deste pacote habilita uma rota do gateway, cria peer VPN ou inicia transferência de imagens clínicas automaticamente.

## Ordem obrigatória de implantação

A implantação deve ocorrer após rotação das credenciais do Object Storage e com uma cópia sanitizada dos ativos no host `evolution-api`. O operador deve instalar os scripts em `/usr/local/sbin`, os exemplos de unidade em `/etc/systemd/system` e os contratos de backup em `/etc/voxelpacs-backup`. Arquivos com segredo ficam com `root:root` e modo `0600`; a senha do Restic permanece em arquivo separado também `0600`.

| Etapa | Ação | Resultado esperado | Estado seguro em falha |
|---|---|---|---|
| 1 | Criar um repositório Restic sob `tenants/<tenant>` | Namespace independente por tenant | Nenhum backup ativo. |
| 2 | Criar `common.env` e `<tenant>.env` a partir dos exemplos | Credenciais separadas do código; `BACKUP_ENABLED=false` | Backup continua bloqueado. |
| 3 | Executar `backup-tenant.sh --tenant <tenant> --validate-only` | Acesso ao repositório e tag tenant validados | Não lê arquivos DICOM nem gera dump. |
| 4 | Fazer backup e restore de objeto sintético em diretório isolado | Snapshot tenant-scoped e restauração sem iniciar containers | Remover o diretório de teste. |
| 5 | Obter aprovação para o marcador `production-enabled` e ativar timer | Primeiro backup real conhecido e auditável | Remover o marcador desabilita execução futura. |
| 6 | Verificar métrica `voxelpacs_tenant_*` e alertas | Saúde técnica e capacidade por tenant | Sem PHI, sem tags ou UIDs DICOM. |

## Controle de recuperação

A restauração exige simultaneamente o tenant, um snapshot explícito e um alvo absoluto que **não pode** pertencer ao runtime de Orthanc ou às configurações ativas. O script valida a tag `tenant:<tenant>` antes de restaurar, não sobe containers e não habilita gateway. Isso impede que um backup do Cliente A seja restaurado na célula B por engano.

## Retenção e imutabilidade

A retenção lógica do Restic somente é aplicada se `RETENTION_PRUNE_APPROVED=true` estiver definido no contrato root-only do tenant. A política de Object Lock do bucket é a camada externa de retenção; o script não tenta contorná-la. A rotação de credenciais expostas anteriormente é pré-requisito antes de habilitar `BACKUP_ENABLED=true`.

## Referências

[1] [Restic — Working with repositories](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html)

[2] [Restic — Backing up](https://restic.readthedocs.io/en/stable/040_backup.html)

[3] [Restic — Restoring from a snapshot](https://restic.readthedocs.io/en/stable/050_restore.html)
