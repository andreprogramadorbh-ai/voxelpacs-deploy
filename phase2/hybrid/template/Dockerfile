FROM orthancteam/orthanc:25.12.3

USER root
RUN set -eux; \
    ln -s /usr/share/orthanc/plugins-available/libOrthancGdcm.so /usr/share/orthanc/plugins/libOrthancGdcm.so; \
    ln -s /usr/share/orthanc/plugins-available/libOrthancPostgreSQLIndex.so /usr/share/orthanc/plugins/libOrthancPostgreSQLIndex.so; \
    ln -s /usr/share/orthanc/plugins-available/libOrthancPostgreSQLStorage.so /usr/share/orthanc/plugins/libOrthancPostgreSQLStorage.so; \
    ln -s /usr/share/orthanc/plugins-available/libOrthancExplorer2.so /usr/share/orthanc/plugins/libOrthancExplorer2.so

USER orthanc
