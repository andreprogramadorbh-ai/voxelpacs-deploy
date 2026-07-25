#!/usr/bin/env python3
"""
VOXEL PACS — DICOMweb Content-Type Fix Proxy v2
================================================
Problema: Orthanc DICOMweb 1.16 retorna Content-Type com aspas no type=
  Ex: multipart/related; type="application/octet-stream; transfer-syntax=..."; boundary=...
Cornerstone3D/OHIF v3.12.5 não parseia Content-Type com aspas → tela preta.

Solução: Proxy transparente na porta 8043 que:
  1. Repassa todas as requisições para o Orthanc (127.0.0.1:8042)
  2. Remove as aspas do type= no Content-Type de resposta
  3. Trata corretamente conexões fechadas pelo cliente (browser cancela request)
  4. Suporte a arquivos grandes (13+ MB) via streaming robusto

v2: Tratamento de ClientConnectionResetError e ConnectionResetError
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

# Regex para remover aspas do type= no Content-Type multipart
CT_FIX_RE = re.compile(r'type="([^"]+)"')


def fix_content_type(ct: str) -> str:
    """Remove aspas do type= no Content-Type multipart/related."""
    if ct and 'multipart/related' in ct:
        fixed = CT_FIX_RE.sub(r'type=\1', ct)
        return fixed
    return ct


async def proxy_handler(request: web.Request) -> web.StreamResponse:
    """Proxy transparente para o Orthanc com correção do Content-Type."""
    # Montar URL de destino
    target_url = ORTHANC_URL + str(request.rel_url)

    # Copiar headers da requisição (exceto Host e hop-by-hop)
    req_headers = {
        k: v for k, v in request.headers.items()
        if k.lower() not in ('host', 'connection', 'transfer-encoding',
                              'keep-alive', 'proxy-authenticate',
                              'proxy-authorization', 'te', 'trailers', 'upgrade')
    }

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
                    headers=resp_headers,
                )

                try:
                    await response.prepare(request)

                    # Stream do body com tratamento de erros de conexão
                    async for chunk in upstream_resp.content.iter_chunked(CHUNK_SIZE):
                        try:
                            await response.write(chunk)
                        except (
                            ConnectionResetError,
                            aiohttp.ClientConnectionResetError,
                            asyncio.CancelledError,
                            BrokenPipeError,
                        ):
                            # Cliente fechou a conexão — comportamento normal
                            # (browser cancela request ao navegar ou recarregar)
                            return response

                    try:
                        await response.write_eof()
                    except (ConnectionResetError, BrokenPipeError):
                        pass

                    return response

                except (
                    ConnectionResetError,
                    aiohttp.ClientConnectionResetError,
                    asyncio.CancelledError,
                    BrokenPipeError,
                ):
                    # Cliente fechou a conexão antes de receber a resposta
                    return response

    except aiohttp.ClientError as e:
        logger.error(f'Upstream error: {e}')
        return web.Response(status=502, text=f'Bad Gateway: {e}')
    except asyncio.CancelledError:
        raise
    except Exception as e:
        logger.error(f'Proxy error: {e}')
        return web.Response(status=500, text=f'Proxy error: {e}')


async def create_app():
    app = web.Application(client_max_size=2 * 1024 ** 3)  # 2 GB
    app.router.add_route('*', '/{path_info:.*}', proxy_handler)
    return app


if __name__ == '__main__':
    import sys
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    app = loop.run_until_complete(create_app())
    web.run_app(
        app,
        host='127.0.0.1',
        port=PROXY_PORT,
        access_log=None,
        loop=loop,
    )
