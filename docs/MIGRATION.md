# Migração de Servidor VOXEL PACS

Este guia explica como migrar toda a infraestrutura do VOXEL PACS de um servidor antigo para um novo servidor Ubuntu 24.04 de forma rápida e segura.

## No Servidor Antigo (Origem)

1. Acesse o diretório do projeto e gere um backup completo:
   ```bash
   cd /caminho/do/voxelpacs-deploy
   bash scripts/backup.sh
   ```
2. O script criará um arquivo em `backups/voxelpacs_backup_YYYYMMDD_HHMMSS.tar.gz`.
3. Baixe este arquivo para sua máquina local ou transfira diretamente para o novo servidor via `scp` ou `rsync`.

## No Servidor Novo (Destino)

1. Clone o repositório limpo:
   ```bash
   git clone https://github.com/andreprogramadorbh-ai/voxelpacs-deploy.git
   cd voxelpacs-deploy
   ```
2. Transfira o arquivo `.tar.gz` gerado no servidor antigo para a pasta `backups/` do novo servidor.
3. Restaure o backup (ele substituirá o `.env` e as configurações):
   ```bash
   bash scripts/restore.sh backups/voxelpacs_backup_YYYYMMDD_HHMMSS.tar.gz
   ```
4. **Importante:** Se o IP do servidor mudou, não se esqueça de atualizar os apontamentos de DNS do seu domínio (`DOMAIN`) para o novo IP.
5. Execute o script de instalação para garantir que o Docker, Nginx, Firewall e SSL sejam reconfigurados corretamente no novo SO:
   ```bash
   bash install.sh
   ```

A migração está concluída sem perda de configurações!
