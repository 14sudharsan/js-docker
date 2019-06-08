# Copyright (c) 2019. TIBCO Software Inc.
# This file is subject to the license terms contained
# in the license file that is distributed with this file.
FROM tomcat:9.0-jre8

# This Dockerfile requires the JasperReports Server WAR file installer file 
# in the resources directory below the Dockerfile.

# COPY the JasperReports Server WAR file installer into the image 

# JasperReports Server WAR file installer names for version 6.3 and prior
# were named jasperreports-server-<version number>-bin.zip
# COPY resources/jasperreports-server*zip /tmp/jasperserver.zip

# JasperReports Server WAR file installer names for version 6.4 and beyond
# are named TIB_js-jrs_<version number>_bin.zip

COPY resources/TIB_js-jrs_*_bin.zip /tmp/jasperserver.zip

RUN apt-get update && apt-get install -y --no-install-recommends apt-utils && \
	apt-get install -y postgresql-client unzip xmlstarlet && \
    rm -rf /var/lib/apt/lists/* && \
	rm -rf $CATALINA_HOME/webapps/ROOT && \
    rm -rf $CATALINA_HOME/webapps/docs && \
    rm -rf $CATALINA_HOME/webapps/examples && \
    rm -rf $CATALINA_HOME/webapps/host-manager && \
    rm -rf $CATALINA_HOME/webapps/manager && \
    unzip /tmp/jasperserver.zip -d /usr/src/jasperreports-server && \
    rm -rf /tmp/* && \
    mv /usr/src/jasperreports-server/jasperreports-server-*/* /usr/src/jasperreports-server && \
	unzip -o -q /usr/src/jasperreports-server/jasperserver-pro.war \
		-d $CATALINA_HOME/webapps/jasperserver-pro && \
	rm -f /usr/src/jasperreports-server/jasperserver-pro.war && \
	chmod +x /usr/src/jasperreports-server/buildomatic/js-ant && \
	chmod +x /usr/src/jasperreports-server/apache-ant/bin/*

ENV PHANTOMJS_VERSION 2.1.1

# Extract phantomjs, move to /usr/local/share/phantomjs, link to /usr/local/bin.
# Comment out if phantomjs not required.
RUN wget \
    "https://bitbucket.org/ariya/phantomjs/downloads/\
phantomjs-2.1.1-linux-x86_64.tar.bz2" \
    -O /tmp/phantomjs.tar.bz2 --no-verbose && \
    tar -xjf /tmp/phantomjs.tar.bz2 -C /tmp && \
    rm -f /tmp/phantomjs.tar.bz2 && \
    mv /tmp/phantomjs*linux-x86_64 /usr/local/share/phantomjs && \
    ln -sf /usr/local/share/phantomjs/bin/phantomjs /usr/local/bin && \
    rm -rf /tmp/*
# In case you wish to download from a different location you can manually
# download the archive and copy from resources/ at build time. Note that you
# also # need to comment out the preceding RUN command
#COPY resources/phantomjs*bz2 /tmp/phantomjs.tar.bz2
#RUN tar -xjf /tmp/phantomjs.tar.bz2 -C /tmp && \
#    rm -f /tmp/phantomjs.tar.bz2 && \
#    mv /tmp/phantomjs*linux-x86_64 /usr/local/share/phantomjs && \
#    ln -sf /usr/local/share/phantomjs/bin/phantomjs /usr/local/bin && \
#    rm -rf /tmp/*
	
# Set default Java options for Tomcat.
# using XX:+UseG1GC - default Java
# use cool Java docker optimizations
ENV JAVA_OPTS="-XX:MaxMetaspaceSize=378m -XX:+UnlockExperimentalVMOptions -XX:+UseCGroupMemoryLimitForHeap"

# Configure tomcat for SSL by default with a self-signed certificate.
# Option to set up JasperReports Server to use HTTPS only.
#
ENV DN_HOSTNAME=${DN_HOSTNAME:-localhost.localdomain} \
    KS_PASSWORD=${KS_PASSWORD:-changeit} \
    JRS_HTTPS_ONLY=${JRS_HTTPS_ONLY:-false} \
    HTTPS_PORT=${HTTPS_PORT:-8443}

RUN keytool -genkey -alias self_signed -dname "CN=${DN_HOSTNAME}" \
		-storetype PKCS12 \
        -storepass "${KS_PASSWORD}" \
        -keypass "${KS_PASSWORD}" \
        -keystore /root/.keystore.p12 && \
	keytool -list -keystore /root/.keystore.p12 -storepass "${KS_PASSWORD}" -storetype PKCS12 && \
    xmlstarlet ed --inplace --subnode "/Server/Service" --type elem \ 
        -n Connector -v "" --var connector-ssl '$prev' \
    --insert '$connector-ssl' --type attr -n port -v "${HTTPS_PORT:-8443}" \
    --insert '$connector-ssl' --type attr -n protocol -v \ 
        "org.apache.coyote.http11.Http11NioProtocol" \
    --insert '$connector-ssl' --type attr -n maxThreads -v "150" \
    --insert '$connector-ssl' --type attr -n SSLEnabled -v "true" \
    --insert '$connector-ssl' --type attr -n scheme -v "https" \
    --insert '$connector-ssl' --type attr -n secure -v "true" \
    --insert '$connector-ssl' --type attr -n clientAuth -v "false" \
    --insert '$connector-ssl' --type attr -n sslProtocol -v "TLS" \
    --insert '$connector-ssl' --type attr -n keystorePass \
        -v "${KS_PASSWORD}"\
    --insert '$connector-ssl' --type attr -n keystoreFile \
        -v "/root/.keystore.p12" \
    ${CATALINA_HOME}/conf/server.xml 

# Expose ports. Note that you must do one of the following:
# map them to local ports at container runtime via "-p 8080:8080 -p 8443:8443"
# or use dynamic ports.
EXPOSE ${HTTP_PORT:-8080} ${HTTPS_PORT:-8443}

COPY scripts/entrypoint.sh /
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

# Default action executed by entrypoint script.
CMD ["run"]
