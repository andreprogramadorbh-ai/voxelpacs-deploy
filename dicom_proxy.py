#!/usr/bin/env python3
"""
VOXEL PACS — DICOMweb Content-Type Fix Proxy v3
================================================
Problemas corrigidos:
  1. Orthanc DICOMweb 1.16 retorna Content-Type com aspas no type=
     Ex: multipart/related; type="application/octet-stream; transfer-syntax=..."
     Cornerstone3D/OHIF v3.12.5 não parseia Content-Type com aspas → tela preta.

  2. Orthanc DICOMweb 1.16 NÃO suporta múltiplos valores no Accept header
     separados por vírgula. O OHIF envia:
       Accept: multipart/related; type=application/octet-stream; transfer-syntax=1.2.840.10008.1.2.1,
               multipart/related; type=application/octet-stream; transfer-syntax=*,
               multipart/related; type=application/octet-stream
     O Orthanc interpreta "1.2.840.10008.1.2.1, multipart/related" como um único
     transfer-syntax inválido → HTTP 500 "Unknown transfer syntax".

  3. ClientConnectionResetError quando o browser cancela requisições (normal).

Solução v3:
  1. Reescreve o Accept header para apenas o PRIMEIRO valor válido antes de
     encaminhar para o Orthanc.
  2. Remove aspas do type= no Content-Type de resposta.
  3. Injeta Authorization Basic automaticamente.
  4. Trata ClientConnectionResetError silenciosamente.
"""
import asyncio
import aiohttp
from aiohttp import web
import re
import logging

logging.basicConfig(level=logging.WARNING)
logger = logging.getLogger('dicom_proxy')

ORTHANC_URL = 'http://127.0.0.1:8042'
PROXY_PORT = 8043
CHUNK_SIZE = 131072  # 128 KB chunks para melhor performance

# Credenciais Orthanc em Base64: vivere_admin:Inlaudo259087@
ORTHANC_AUTH = 'Basic dml2ZXJlX2FkbWluOklubGF1ZG8yNTkwODdA'

# Regex para remover aspas do type= no Content-Type multipart/related
CT_FIX_RE = re.compile(r'type="([^"]+)"')


def fix_content_type(ct: str) -> str:
    """Remove aspas do type= no Content-Type multipart/related."""
    if ct and 'multipart/related' in ct:
        fixed = CT_FIX_RE.sub(r'type=\1', ct)
        return fixed
    return ct


def fix_accept_header(accept: str) -> str:
    """
    Orthanc DICOMweb 1.16 não suporta múltiplos valores no Accept header.
    Reescreve para apenas o primeiro valor válido (transfer-syntax=1.2.840.10008.1.2.1).
    
    Entrada: "multipart/related; type=application/octet-stream; transfer-syntax=1.2.840.10008.1.2.1, ..."
    Saída:   "multipart/related; type=application/octet-stream; transfer-syntax=1.2.840.10008.1.2.1"
    """
    if not accept or 'multipart/related' not in accept:
        return accept
    
    # Extrair apenas o primeiro segmento (antes da primeira vírgula que separa
    # múltiplos tipos de mídia — não confundir com vírgulas dentro de parâmetros)
    # O Accept header para WADO-RS tem a forma:
    # "multipart/related; type=...; transfer-syntax=UID, multipart/related; ..."
    # Precisamos dividir por ", multipart/related" para separar os tipos
    parts = re.split(r',\s*multipart/related', accept)
    
    if len(parts) > 1:
        # Pegar apenas o primeiro tipo — que tem transfer-syntax=1.2.840.10008.1.2.1
        first = parts[0].strip()
        # Verificar se tem um transfer-syntax específico (não *)
        if 'transfer-syntax=1.2.840.10008.1.2.1' in first:
            return first
        # Se o primeiro não tem UID específico, usar apenas octet-stream sem transfer-syntax
        return 'multipart/related; type=application/octet-stream; transfer-syntax=1.2.840.10008.1.2.1'
    
    return accept


async def proxy_handler(request: web.Request) -> web.StreamResponse:
    """Proxy transparente para o Orthanc com correção do Accept e Content-Type."""
    # Montar URL de destino
    target_url = ORTHANC_URL + str(request.rel_url)

    # Copiar headers da requisição (exceto Host e hop-by-hop)
    req_headers = {
        k: v for k, v in request.headers.items()
        if k.lower() not in ('host', 'connection', 'transfer-encoding',
                              'keep-alive', 'proxy-authenticate',
                              'proxy-authorization', 'te', 'trailers', 'upgrade')
    }

    # Injetar credenciais Orthanc (o cliente não precisa enviar Authorization)
    req_headers['Authorization'] = ORTHANC_AUTH

    # Corrigir Accept header para compatibilidade com Orthanc DICOMweb 1.16
    if 'Accept' in req_headers:
        original_accept = req_headers['Accept']
        fixed_accept = fix_accept_header(original_accept)
        if fixed_accept != original_accept:
            logger.debug(f'Accept rewritten: {original_accept!r} → {fixed_accept!r}')
        req_headers['Accept'] = fixed_accept

    # Ler body da requisição
    try:
        body = await request.read()
    except Exception:
        body = None

    timeout = aiohttp.ClientTimeout(
        total=600,
        connect=10,
        sock_read=600,
        sock_connect=10
    )
    connector = aiohttp.TCPConnector(limit=100, keepalive_timeout=30)

    try:
        async with aiohttp.ClientSession(
            timeout=timeout,
            connector=connector,
            connector_owner=True
        ) as session:
            async with session.request(
                method=request.method,
                url=target_url,
                headers=req_headers,
                data=body if body else None,
                allow_redirects=False,
                ssl=False,
            ) as upstream_resp:
                # Corrigir o Content-Type
                ct_original = upstream_resp.headers.get('Content-Type', '')
                ct_fixed = fix_content_type(ct_original)

                # Montar headers de resposta (excluir hop-by-hop)
                resp_headers = {}
                skip_headers = {
                    'connection', 'transfer-encoding', 'keep-alive',
                    'proxy-authenticate', 'proxy-authorization',
                    'te', 'trailers', 'upgrade'
                }
                for k, v in upstream_resp.headers.items():
                    if k.lower() in skip_headers:
                        continue
                    if k.lower() == 'content-type':
                        resp_headers[k] = ct_fixed
                    else:
                        resp_headers[k] = v

                # Criar resposta de streaming
                response = web.StreamResponse(
                    status=upstream_resp.status,
                    reason=upstream_resp.reason,
                    headers=resp_headers
                )
                await response.prepare(request)

                # Stream do corpo em chunks
                try:
                    async for chunk in upstream_resp.content.iter_chunked(CHUNK_SIZE):
                        await response.write(chunk)
                except (
                    ConnectionResetError,
                    aiohttp.ClientConnectionResetError,
                    aiohttp.ServerDisconnectedError,
                    asyncio.CancelledError,
                    BrokenPipeError,
                ) as e:
                    # Browser cancelou a requisição — comportamento normal
                    logger.debug(f'Client disconnected (normal): {type(e).__name__}')
                    return response

                await response.write_eof()
                return response

    except asyncio.CancelledError:
        raise
    except Exception as e:
        logger.error(f'Proxy error for {request.rel_url}: {type(e).__name__}: {e}')
        return web.Response(
            status=502,
            text=f'Proxy error: {type(e).__name__}: {e}',
            content_type='text/plain'
        )


async def main():
    app = web.Application()
    app.router.add_route('*', '/{path_info:.*}', proxy_handler)
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, '127.0.0.1', PROXY_PORT)
    await site.start()
    print(f'======== Running on http://127.0.0.1:{PROXY_PORT} ========')
    print('(Press CTRL+C to quit)')
    await asyncio.Event().wait()


if __name__ == '__main__':
    asyncio.run(main())
