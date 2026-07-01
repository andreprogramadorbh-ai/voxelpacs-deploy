# Instalação do VOXEL PACS

Este documento detalha o processo de instalação da infraestrutura de deploy do VOXEL PACS (OHIF Viewer + Nginx + SSL) em um servidor Ubuntu 24.04.

## Pré-requisitos

1.  **Servidor Limpo:** Recomendamos um servidor com instalação limpa do **Ubuntu 24.04 LTS**.
2.  **Acesso Root:** Você deve ter acesso de superusuário (root) ou privilégios `sudo`.
3.  **Domínio Configurado:** Um domínio ou subdomínio (ex: `view.seudominio.com.br`) apontando para o IP público deste servidor.
4.  **Servidor Orthanc:** O endereço, porta e credenciais do seu servidor Orthanc já devem estar configurados e acessíveis pela internet.

## Passo a Passo

### 1. Clonar o Repositório

Faça login no seu servidor via SSH e clone este repositório:

```bash
cd /opt
git clone https://github.com/VOXELPACS/voxelpacs-deploy.git
cd voxelpacs-deploy
```

### 2. Configurar as Variáveis de Ambiente

Copie o arquivo de exemplo `.env.example` para `.env`:

```bash
cp .env.example .env
```

Edite o arquivo `.env` com o seu editor de texto preferido (ex: `nano` ou `vim`):

```bash
nano .env
```

Preencha as seguintes variáveis:

*   `DOMAIN`: O domínio que você configurou (ex: `view.voxelpacs.com.br`).
*   `CERTBOT_EMAIL`: Seu e-mail para receber notificações de renovação do SSL.
*   `ORTHANC_HOST`: O IP ou domínio do seu servidor Orthanc.
*   `ORTHANC_PORT`: A porta HTTP do Orthanc (padrão: 8042).
*   `ORTHANC_PROTOCOL`: O protocolo de conexão (http ou https).
*   `GENERATE_SSL`: Mantenha como `yes` para gerar o certificado SSL automaticamente durante a instalação.

### 3. Executar o Instalador

Dê permissão de execução ao script de instalação e execute-o:

```bash
chmod +x install.sh
./install.sh
```

O script fará o seguinte de forma automatizada:
1.  Verificará a versão do sistema operacional.
2.  Instalará o Docker Engine e o Docker Compose Plugin (se não estiverem instalados).
3.  Criará os diretórios necessários.
4.  Configurará o Nginx e o OHIF Viewer com base nas variáveis do `.env`.
5.  Baixará as imagens Docker necessárias.
6.  Iniciará os containers em background.
7.  Validará a saúde dos containers.
8.  (Opcional) Gerará o certificado SSL via Let's Encrypt.

### 4. Validação

Após a conclusão da instalação, o script exibirá um resumo. Você pode verificar a saúde do sistema a qualquer momento executando:

```bash
./healthcheck.sh
```

Acesse `https://SEU_DOMINIO` no seu navegador para verificar se o OHIF Viewer está funcionando corretamente.

## Próximos Passos

*   Consulte [BACKUP.md](BACKUP.md) para configurar backups regulares.
*   Consulte [TROUBLESHOOTING.md](TROUBLESHOOTING.md) caso encontre algum problema.
