# Homologação sintética multi-tenant — VOXEL PACS

Este roteiro valida a construção antes de imagens clínicas, conexões de clientes reais ou criação de B/C/D em produção. Todos os objetos de teste devem ser DICOM sintéticos, com paciente, identificadores e UIDs próprios de laboratório. Não consultar, copiar, listar ou restaurar acervo clínico durante esta fase.

## Pré-condições de implantação

| Controle | Condição para iniciar | Evidência |
|---|---|---|
| Código da aplicação | Migration aplicada em janela aprovada, sem erro e com backup lógico do banco | Índices `uq_cell_tenant`, `uq_cell_servidor` e `uq_estudo_servidor_orthanc` presentes. |
| Célula | Tenant, servidor Orthanc privado e linha em `bi_tenant_orthanc_cells` coerentes | Um tenant e um servidor por célula; rota do gateway ainda desabilitada. |
| Viewer | `viewer_url` exclusivo e configuração desktop completa para o tenant | Abertura do token não pode cair em URL global. |
| Gateway | Política YAML validada, listener correto e rota ainda `enabled: false` | Testes locais de política e encaminhamento aprovados. |
| Backup | Repositório Restic `tenants/<slug>`, acesso validado e restore sintético aprovado | Snapshot só do tenant, sem dados clínicos. |
| Credenciais | Tokens e chaves previamente expostos foram rotacionados e arquivos temporários removidos | Registro de rotação sem valores secretos. |

## Matriz por perfil

| Perfil | Origem permitida | Listener | Cifra mínima | Identidade validada | Resultado proibido |
|---|---|---|---|---|---|
| `vpn_mtls` | Peer WireGuard exclusivo | DICOM TLS | VPN + TLS 1.2 ou superior + certificado cliente | IP de túnel, Calling AE, Called AE, cadeia de certificados | Conexão sem TLS, certificado ausente ou AE divergente. |
| `vpn_only` | Peer WireGuard exclusivo | DICOM interno no túnel | WireGuard autenticado | IP de túnel, Calling AE e Called AE | Acesso por Internet ou de qualquer peer não associado ao tenant. |
| `site_router` | Roteador DICOM local do cliente, sobre peer WireGuard exclusivo | Conforme capacidade do roteador | WireGuard; TLS quando suportado | Peer, IP de túnel, Calling AE do roteador/modalidade e Called AE | Modalidade legada exposta diretamente na Internet. |

## Casos de teste obrigatórios

| ID | Cenário sintético | Resultado de aceite |
|---|---|---|
| H-01 | C-ECHO autorizado pelo perfil correspondente | Associação aceita e auditoria técnica registra tenant, perfil, AEs e resultado, sem PHI/UID. |
| H-02 | C-STORE autorizado com objeto sintético | Instância chega apenas ao diretório/índice da célula alvo; retorno de sucesso. |
| H-03 | Calling AE inválido | Rejeição no estágio de associação; nenhum objeto ou job criado. |
| H-04 | Called AE de outro tenant | Rejeição no estágio de associação; nenhum encaminhamento. |
| H-05 | IP de túnel/peer não cadastrado | Rejeição; firewall e gateway não aceitam a associação. |
| H-06 | `vpn_mtls` sem certificado, com CA não confiável ou TLS antigo | Rejeição; não há downgrade para listener sem TLS. |
| H-07 | Viewer do Tenant A tentando abrir ID de estudo do Tenant B | 404/403 sem revelar existência; token não é emitido. |
| H-08 | Falha de inserção de token do viewer | Tela de erro 503 controlada; nenhum redirect com `StudyInstanceUID`. |
| H-09 | Viewer desktop de célula isolada sem configuração própria | Falha controlada; host/porta/AE global não são usados. |
| H-10 | Backup de objeto sintético do tenant e restore em diretório isolado | Snapshot/tag pertencem ao mesmo tenant e nenhum container de runtime é iniciado. |
| H-11 | Teste de disco e healthcheck | Métricas técnicas por tenant disponíveis; alerta antes do limiar aprovado. |

## Ordem de ativação

A ordem de ativação é sempre: aplicar código/migration e validar banco; instalar rotinas sem habilitar backup produtivo; executar H-01 a H-11; corrigir qualquer falha; habilitar backup do tenant; validar nova restauração sintética; obter aprovação formal do responsável técnico; e somente então habilitar a rota do gateway para o tenant. O Cliente A só pode ser ativado com `vpn_mtls` após o certificado de cliente ser emitido a partir de CSR válido e a cadeia mútua ser validada.

Clientes sem TLS devem usar `vpn_only` ou `site_router`; esses perfis não autorizam DICOM aberto na Internet. A VPN protege a associação no trecho externo, e o gateway mantém a validação de tenant antes do Orthanc.

## Critérios de bloqueio

A ativação é bloqueada se faltar qualquer um destes elementos: rotação de credenciais expostas; migração com backup; viewer específico da célula; backup/restauração sintética; política de gateway habilitada apenas para o tenant correto; verificação de rejeições; e isolamento de API/viewer aprovado. Não existe exceção para “teste rápido” com dados de paciente.

## Referências

[1] [pynetdicom — Association Control Service Element](https://pydicom.github.io/pynetdicom/stable/reference/generated/pynetdicom.acse.ACSE.html)

[2] [Orthanc Book — PostgreSQL plugins](https://orthanc.uclouvain.be/book/plugins/postgresql.html)

[3] [Restic Documentation](https://restic.readthedocs.io/en/stable/)
