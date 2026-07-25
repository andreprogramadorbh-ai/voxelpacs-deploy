#!/usr/bin/env python3
"""
VOXEL PACS — DICOMweb Content-Type Fix Proxy
=============================================
Problema: Orthanc DICOMweb 1.16 retorna Content-Type com aspas no type=
  Ex: multipart/related; type="application/octet-stream; transfer-syntax=..."; boundary=...

Cornerstone3D/OHIF v3.12.5 não parseia Content-Type com aspas → tela preta.

Solução: Proxy transparente na porta 8043 que:
  1. Repassa todas as requisições para o Orthanc (127.0.0.1:8042)
  2. Remove as aspas do type= no Content-Type de resposta
  3. Mantém todos os outros headers intactos

Nginx redireciona /dicom-web/ para este proxy (127.0.0.1:8043) em vez do Orthanc direto.
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

# Regex para remover aspas do type= no Content-Type multipart
CT_FIX_RE = re.compile(r'type="([^"]+)"')


def fix_content_type(ct: str) -> str:
    """Remove aspas do type= no Content-Type multipart/related."""
    if ct and 'multipart/related' in ct:
        fixed = CT_FIX_RE.sub(r'type=\1', ct)
        if fixed != ct:
            logger.info(f'Content-Type fixed: {ct[:80]} → {fixed[:80]}')
        return fixed
    return ct


async def proxy_handler(request: web.Request) -> web.StreamResponse:
    """Proxy transparente para o Orthanc com correção do Content-Type."""
    # Montar URL de destino
    target_url = ORTHANC_URL + str(request.rel_url)

    # Copiar headers da requisição (exceto Host)
    req_headers = {
        k: v for k, v in request.headers.items()
        if k.lower() not in ('host', 'connection', 'transfer-encoding')
    }

    # Ler body da requisição
    body = await request.read()

    timeout = aiohttp.ClientTimeout(total=300)

    async with aiohttp.ClientSession(timeout=timeout) as session:
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

            # Montar headers de resposta
            resp_headers = {}
            for k, v in upstream_resp.headers.items():
                if k.lower() in ('connection', 'transfer-encoding', 'keep-alive'):
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
            await response.prepare(request)

            # Stream do body
            async for chunk in upstream_resp.content.iter_chunked(65536):
                await response.write(chunk)

            await response.write_eof()
            return response


async def create_app():
    app = web.Application()
    app.router.add_route('*', '/{path_info:.*}', proxy_handler)
    return app


if __name__ == '__main__':
    app = asyncio.get_event_loop().run_until_complete(create_app())
    web.run_app(app, host='127.0.0.1', port=PROXY_PORT, access_log=None)
