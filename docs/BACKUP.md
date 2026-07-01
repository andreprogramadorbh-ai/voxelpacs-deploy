# Backup e Restauração do VOXEL PACS

Este documento explica como realizar backups da configuração e dos certificados SSL do ambiente VOXEL PACS, bem como restaurá-los.

**Nota:** Como esta infraestrutura (OHIF + Nginx) não possui banco de dados próprio (o banco de dados e as imagens DICOM residem no servidor Orthanc), o backup consiste apenas nos arquivos de configuração, variáveis de ambiente e certificados SSL.

## Como Fazer Backup

Para criar um backup manual, execute o script:

```bash
cd /opt/voxelpacs-deploy
./backup.sh
```

O script criará um arquivo compactado (ex: `voxelpacs_backup_20260701_120000.tar.gz`) no diretório definido pela variável `BACKUP_DIR` no seu arquivo `.env` (o padrão é `./backups`).

### O que está incluído no backup?
- O arquivo `.env` (contendo todas as variáveis).
- O diretório `config/` (configurações do Nginx e OHIF).
- O diretório de certificados do Let's Encrypt (`/etc/letsencrypt/`), se existir.

### Automatizando o Backup (Cron)

É recomendável configurar o backup para ser executado automaticamente (ex: diariamente).

1. Abra o editor do crontab:
   ```bash
   crontab -e
   ```
2. Adicione a seguinte linha para rodar o backup todos os dias às 02:00 da manhã:
   ```cron
   0 2 * * * cd /opt/voxelpacs-deploy && ./backup.sh >> /var/log/voxelpacs_backup.log 2>&1
   ```

## Como Restaurar um Backup

Para restaurar um backup previamente criado, use o script `restore.sh` passando o caminho do arquivo de backup como argumento.

**Atenção:** A restauração sobrescreverá as configurações atuais e os certificados SSL.

```bash
cd /opt/voxelpacs-deploy
./restore.sh backups/voxelpacs_backup_20260701_120000.tar.gz
```

Após a restauração, reinicie os containers para aplicar as configurações restauradas:

```bash
docker compose down
docker compose up -d
```
