# Resolução de Problemas (Troubleshooting)

Este guia ajuda a diagnosticar e resolver os problemas mais comuns encontrados na infraestrutura do VOXEL PACS.

## 1. Como visualizar os logs

A primeira etapa na resolução de qualquer problema é verificar os logs dos containers Docker.

Para ver os logs do Nginx:
```bash
docker logs voxelpacs-nginx
```

Para ver os logs do OHIF (útil durante a inicialização, pois o OHIF roda no navegador do cliente após ser servido):
```bash
docker logs voxelpacs-ohif
```

Para ver os logs de ambos os serviços em tempo real:
```bash
cd /opt/voxelpacs-deploy
docker compose logs -f
```

## 2. O site não carrega (Erro 502 Bad Gateway)

**Causa provável:** O Nginx está rodando, mas não consegue se comunicar com o container do OHIF ou com o servidor Orthanc.

**Soluções:**
1. Verifique se o container do OHIF está rodando: `docker ps`. Se não estiver, tente iniciá-lo: `docker compose up -d ohif`.
2. Verifique se o servidor Orthanc remoto está online e acessível a partir do servidor do Nginx. Teste com `curl`:
   ```bash
   curl -I http://IP_DO_ORTHANC:8042
   ```
3. Verifique os logs do Nginx para ver a mensagem de erro exata.

## 3. O site não carrega (Tempo limite / Timeout)

**Causa provável:** O firewall está bloqueando as portas 80 ou 443, ou o container do Nginx não está rodando.

**Soluções:**
1. Verifique se o Nginx está rodando: `docker ps`.
2. Verifique as regras de firewall. Se estiver usando UFW:
   ```bash
   sudo ufw status
   ```
   Certifique-se de que as portas 80 e 443 estão permitidas. Se não estiverem, execute `./scripts/firewall.sh`.
3. Verifique as configurações de rede na sua provedora de nuvem (AWS Security Groups, regras de firewall da DigitalOcean, etc.).

## 4. Erro de Certificado SSL (Aviso de Inseguro no navegador)

**Causa provável:** O certificado Let's Encrypt não foi gerado corretamente, expirou, ou o Nginx não foi recarregado após a renovação.

**Soluções:**
1. Verifique se os certificados existem: `sudo ls -l /etc/letsencrypt/live/SEU_DOMINIO/`.
2. Se não existirem, tente gerá-los manualmente: `./scripts/generate-ssl.sh`.
3. Se existirem, verifique a validade: `sudo certbot certificates`.
4. Se foram renovados recentemente, force o recarregamento do Nginx: `docker exec voxelpacs-nginx nginx -s reload`.

## 5. O OHIF carrega, mas não mostra as imagens (Erro de DICOMweb / CORS)

**Causa provável:** O OHIF não consegue se comunicar com o Orthanc devido a problemas de CORS, URL incorreta ou o Orthanc não está respondendo adequadamente às requisições DICOMweb.

**Soluções:**
1. Abra as Ferramentas de Desenvolvedor do navegador (F12) e verifique a aba "Console" e "Network" (Rede) para erros em vermelho (especialmente requisições para `/dicom-web/...`).
2. Verifique se o Orthanc remoto está configurado para aceitar requisições do seu domínio. Se o Nginx do VOXEL PACS está fazendo o proxy do tráfego DICOMweb (recomendado para evitar problemas de CORS), verifique a configuração em `config/nginx/default.conf` no bloco `location /dicom-web/`.
3. Verifique o arquivo `config/ohif/app-config.js`. A `wadoRoot` e `qidoRoot` devem apontar para a URL correta (geralmente através do seu próprio domínio e Nginx, ex: `https://view.seudominio.com.br/dicom-web`).

## 6. Problemas ao usar os scripts (.sh)

**Causa provável:** O script não tem permissão de execução ou contém caracteres de fim de linha do Windows (CRLF).

**Soluções:**
1. Dê permissão de execução: `chmod +x *.sh scripts/*.sh`.
2. Se você editou o script no Windows, converta os finais de linha para o formato Unix:
   ```bash
   sudo apt install dos2unix
   dos2unix *.sh scripts/*.sh
   ```

## Precisa de mais ajuda?

Execute o script de verificação de saúde para um diagnóstico rápido:
```bash
./healthcheck.sh
```
