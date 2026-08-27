# Fontes técnicas externas — Fase 2

| Tema | Fonte | Decisão aplicada |
|---|---|---|
| Negociação de associação DICOM no gateway | [pynetdicom — ACSE](https://pydicom.github.io/pynetdicom/stable/reference/generated/pynetdicom.acse.ACSE.html) | A associação não autorizada deve receber `A-ASSOCIATE-RJ` permanente, antes de qualquer DIMSE. |
| Identidades durante a requisição | [pynetdicom — A-ASSOCIATE](https://pydicom.github.io/pynetdicom/dev/reference/generated/pynetdicom.pdu_primitives.A_ASSOCIATE.html) | No evento `EVT_REQUESTED`, o gateway lê Calling/Called AE do primitivo recebido. |
| TLS e listeners no pynetdicom | [pynetdicom — ApplicationEntity](https://pydicom.github.io/pynetdicom/stable/reference/generated/pynetdicom.ae.ApplicationEntity.html) | O perfil `vpn_mtls` fica em listener TLS separado do perfil `vpn_only`/`site_router`. |
| Índice PostgreSQL no Orthanc | [Orthanc Book — PostgreSQL plugins](https://orthanc.uclouvain.be/book/plugins/postgresql.html) | O PostgreSQL é usado somente como índice; o template limita `IndexConnectionsCount` e usa pool dinâmico por tenant. |
| Backup e restauração cifrados | [Restic — documentação](https://restic.readthedocs.io/en/stable/) | Cada tenant recebe um namespace Restic próprio, tags próprias e restauração com snapshot explícito. |
