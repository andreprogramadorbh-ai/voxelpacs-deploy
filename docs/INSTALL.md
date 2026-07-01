# Instalação do VOXEL PACS

Este guia detalha o processo de instalação do ambiente VOXEL PACS. O script `install.sh` foi projetado para ser totalmente automatizado e idempotente.

## Pré-requisitos
- Servidor Ubuntu 24.04 LTS limpo.
- Usuário `root` ou com privilégios `sudo` sem senha.
- Domínio apontado para o IP do servidor (ex: `view.voxelpacs.com.br`).
- Servidor Orthanc remoto acessível.

## Passo a passo

1. **Clone o repositório:**
   ```bash
   git clone https://github.com/andreprogramadorbh-ai/voxelpacs-deploy.git
   cd voxelpacs-deploy
   ```

2. **Configure as variáveis:**
   ```bash
   cp .env.example .env
   nano .env
   ```
   Preencha obrigatoriamente: `DOMAIN`, `CERTBOT_EMAIL`, `ORTHANC_HOST`, `ORTHANC_PORT`, `ORTHANC_USERNAME`, `ORTHANC_PASSWORD`.

3. **Execute a instalação:**
   ```bash
   bash install.sh
   ```

## O que o script faz?
1. Detecta o SO e instala Docker/Compose V2 (se necessário).
2. Instala Nginx, Certbot e configura o UFW (Firewall) liberando portas 22, 80 e 443.
3. Gera o arquivo `app-config.js` do OHIF dinamicamente.
4. Gera as configurações de Proxy Reverso no Nginx.
5. Sobe o container Docker do OHIF.
6. Emite o certificado SSL via Let's Encrypt.
7. Valida as conexões com o Orthanc remoto e DICOMweb.
