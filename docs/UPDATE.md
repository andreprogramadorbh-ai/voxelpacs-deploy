# Atualização do VOXEL PACS

Este documento explica como atualizar a infraestrutura de deploy do VOXEL PACS (OHIF Viewer + Nginx) sem causar indisponibilidade prolongada.

## Como funciona a atualização?

O script de atualização (`update.sh`) realiza as seguintes ações:
1. Faz pull das últimas alterações deste repositório Git.
2. Faz pull das últimas imagens Docker (`ohif/app:latest` e `nginx:alpine`).
3. Recria os containers Docker apenas se houver alterações nas imagens ou configurações.
4. Remove imagens antigas para economizar espaço em disco.

## Passo a Passo

### 1. Executar o Script de Atualização

Acesse o diretório onde o repositório foi clonado (geralmente `/opt/voxelpacs-deploy` ou `/home/ubuntu/voxelpacs-deploy`) e execute o script:

```bash
cd /opt/voxelpacs-deploy
./update.sh
```

### 2. Validação

Após a atualização, o script executará automaticamente uma verificação básica. Para uma verificação completa, execute:

```bash
./healthcheck.sh
```

## Considerações Importantes

*   **Sem Downtime:** O Docker Compose tenta recriar os containers com o mínimo de interrupção possível.
*   **Backup:** É altamente recomendável realizar um backup antes de qualquer atualização importante. Veja [BACKUP.md](BACKUP.md).
*   **Customizações:** Se você fez alterações manuais nos arquivos de configuração dentro de `config/` que não estão no controle de versão, elas podem ser sobrescritas dependendo de como você gerencia o Git localmente. Use variáveis no `.env` sempre que possível.
