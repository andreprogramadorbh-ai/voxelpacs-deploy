# Migração de Servidor do VOXEL PACS

Este guia descreve como migrar a infraestrutura do VOXEL PACS (OHIF Viewer + Nginx) de um servidor antigo para um novo.

## Passo a Passo

### No Servidor Antigo

1.  **Gere um Backup Completo:**
    Execute o script de backup para salvar todas as configurações, certificados SSL e o arquivo `.env`.

    ```bash
    cd /opt/voxelpacs-deploy
    ./backup.sh
    ```

2.  **Transfira o Arquivo de Backup:**
    Copie o arquivo gerado (ex: `voxelpacs_backup_20260701_120000.tar.gz`) para o novo servidor. Você pode usar `scp`, `rsync` ou qualquer outra ferramenta de transferência de arquivos.

    ```bash
    scp /opt/voxelpacs-deploy/backups/voxelpacs_backup_*.tar.gz root@NOVO_IP:/tmp/
    ```

### No Novo Servidor

1.  **Clone o Repositório:**
    Prepare o novo servidor clonando o repositório.

    ```bash
    cd /opt
    git clone https://github.com/VOXELPACS/voxelpacs-deploy.git
    cd voxelpacs-deploy
    ```

2.  **Restaure o Backup:**
    Execute o script de restauração, apontando para o arquivo de backup transferido.

    ```bash
    ./restore.sh /tmp/voxelpacs_backup_*.tar.gz
    ```

3.  **Ajuste o DNS:**
    Acesse o painel do seu provedor de domínio (Registro.br, Cloudflare, AWS Route 53, etc.) e altere o apontamento do registro A ou CNAME para o IP do **novo servidor**.

4.  **Aguarde a Propagação do DNS:**
    A propagação do DNS pode levar de alguns minutos a algumas horas.

5.  **Instale o Ambiente:**
    Após confirmar que o DNS já aponta para o novo IP (você pode verificar com `ping SEU_DOMINIO`), execute o instalador. Como os certificados SSL já foram restaurados, você pode desativar a geração de um novo certificado temporariamente no `.env` (`GENERATE_SSL=no`), ou deixar como `yes` se preferir que o script valide/renove.

    ```bash
    ./install.sh
    ```

6.  **Validação:**
    Execute o healthcheck para garantir que tudo está funcionando.

    ```bash
    ./healthcheck.sh
    ```
