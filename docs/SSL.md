# Certificados SSL no VOXEL PACS

Este documento explica como o VOXEL PACS gerencia os certificados SSL via Let's Encrypt e Certbot.

## Geração Automática na Instalação

Durante a execução do `./install.sh`, se a variável `GENERATE_SSL` no arquivo `.env` estiver definida como `yes`, o script executará automaticamente o script `scripts/generate-ssl.sh`.

Este script utiliza o Certbot para solicitar um certificado gratuito da Let's Encrypt para o domínio especificado na variável `DOMAIN`.

**Requisitos para a geração bem-sucedida:**
1. O domínio (`DOMAIN`) deve estar apontando corretamente para o IP público do servidor (Registro A ou CNAME).
2. As portas 80 (HTTP) e 443 (HTTPS) devem estar abertas no firewall.
3. O Nginx deve estar configurado corretamente para responder ao desafio ACME na porta 80. O arquivo `config/nginx/default.conf` já inclui essa configuração (`location /.well-known/acme-challenge/`).

## Renovação Automática

Os certificados da Let's Encrypt são válidos por 90 dias. A renovação deve ser automatizada.

O pacote Certbot instalado no sistema operacional (Ubuntu) geralmente configura um timer do systemd ou um cron job automaticamente para verificar e renovar certificados prestes a expirar.

No entanto, como estamos usando o Nginx dentro do Docker, o Certbot nativo precisa saber como recarregar o Nginx após uma renovação bem-sucedida.

### Configurando o Hook de Renovação

Para garantir que o Nginx no Docker recarregue os novos certificados, crie um hook de deploy para o Certbot:

1. Crie o arquivo de hook:
   ```bash
   sudo nano /etc/letsencrypt/renewal-hooks/deploy/reload-nginx-docker.sh
   ```

2. Adicione o seguinte conteúdo:
   ```bash
   #!/bin/bash
   # Recarrega o Nginx dentro do container Docker
   docker exec voxelpacs-nginx nginx -s reload
   ```

3. Torne o script executável:
   ```bash
   sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx-docker.sh
   ```

### Testando a Renovação

Você pode simular o processo de renovação para garantir que tudo está funcionando (incluindo o hook):

```bash
sudo certbot renew --dry-run
```

## Geração Manual

Se você precisar gerar ou regenerar o certificado manualmente, execute:

```bash
cd /opt/voxelpacs-deploy
./scripts/generate-ssl.sh
```

## Usando Certificados Próprios

Se você comprou um certificado SSL de uma Autoridade Certificadora (CA) comercial em vez de usar o Let's Encrypt:

1. Defina `GENERATE_SSL=no` no arquivo `.env`.
2. Coloque os arquivos do seu certificado (chave privada e certificado completo) no servidor.
3. Edite o arquivo `config/nginx/ssl.conf` e ajuste os caminhos `ssl_certificate` e `ssl_certificate_key` para apontar para os seus arquivos.
4. Mapeie o diretório contendo seus certificados no `docker-compose.yml` para dentro do container do Nginx.
5. Reinicie os containers: `docker compose down && docker compose up -d`.
