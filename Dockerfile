#####################################################################
# COMPILE VDR BUILD
# Modified to run in my qnap+sonytv setup
#####################################################################
FROM alpine:3.8 AS vdr-build
MAINTAINER CodeKing <frank@herrmann.to>

USER root

# INSTALL DEPENDENCIES
RUN apk --update add build-base freetype-dev fontconfig-dev gettext-dev \
	libjpeg-turbo-dev libcap-dev pugixml-dev curl-dev git bzip2 libexecinfo-dev \
	ncurses-dev bash imagemagick-dev pcre-dev libressl-dev zip g++ && \
    rm -rf /var/cache/apk/*

# SWITCH TO BUILD DIR
RUN mkdir -p /build
WORKDIR /build

# INSTALL CXXTOOLS
RUN wget http://www.tntnet.org/download/cxxtools-2.2.1.tar.gz
RUN tar -xf cxxtools-2.2.1.tar.gz

WORKDIR cxxtools-2.2.1
RUN ./configure && make -j 4 && make install
WORKDIR ../

# INSTALL TNTNET
RUN wget http://www.tntnet.org/download/tntnet-2.2.1.tar.gz
RUN tar -xf tntnet-2.2.1.tar.gz

WORKDIR tntnet-2.2.1
RUN ./configure && make -j 4 && make install
WORKDIR ../

# VDR & ROBOTV VERSION
ENV ROBOTV_VERSION="master"
ENV VDR_VERSION="2.4.0"

# DOWNLOAD VDR SERVER & PLUGINS
RUN wget ftp://ftp.tvdr.de/vdr/vdr-$VDR_VERSION.tar.bz2
RUN tar -jxf vdr-$VDR_VERSION.tar.bz2
RUN git clone -b $ROBOTV_VERSION https://github.com/pipelka/vdr-plugin-robotv.git vdr-$VDR_VERSION/PLUGINS/src/robotv
RUN git clone https://github.com/manio/vdr-plugin-dvbapi.git vdr-$VDR_VERSION/PLUGINS/src/dvbapi
RUN git clone https://github.com/vdr-projects/vdr-plugin-epgsearch.git vdr-$VDR_VERSION/PLUGINS/src/epgsearch
RUN git clone -b robotv https://github.com/pipelka/vdr-plugin-satip.git vdr-$VDR_VERSION/PLUGINS/src/satip
RUN git clone https://github.com/vdr-projects/vdr-plugin-streamdev.git vdr-$VDR_VERSION/PLUGINS/src/streamdev
RUN git clone https://github.com/yavdr/vdr-plugin-restfulapi.git vdr-$VDR_VERSION/PLUGINS/src/restfulapi
RUN git clone https://github.com/FernetMenta/vdr-plugin-vnsiserver.git vdr-$VDR_VERSION/PLUGINS/src/vnsiserver
RUN git clone https://github.com/flensrocker/vdr-plugin-dummydevice vdr-$VDR_VERSION/PLUGINS/src/dummydevice
RUN git clone https://github.com/flensrocker/vdr-plugin-noepg vdr-$VDR_VERSION/PLUGINS/src/noepg

WORKDIR vdr-$VDR_VERSION

# COPY TEMPLATE FILES
COPY templates/vdr/Make.* /build/vdr-$VDR_VERSION/

# RUN PATCHES
RUN mkdir -p /build/patches
COPY patches/ /build/patches/

RUN for patch in `ls /build/patches/vdr`; do \
        echo ${patch} ; \
        patch -p1 < /build/patches/vdr/${patch} ; \
    done

WORKDIR PLUGINS/src/epgsearch
RUN patch -p1 < /build/patches/epgsearch/install-conf.patch
WORKDIR ../../..

# CREATE DIRECTORIES
RUN mkdir -p /opt/vdr

# COMPILE VDR
RUN make -j 4 && make install

# STRIP DEBUG INFORMATIONS
RUN for plugin in robotv dvbapi epgsearch dummydevice satip streamdev-server vnsiserver restfulapi noepg ; do \
        strip -s --strip-debug /opt/vdr/lib/libvdr-${plugin}.so.* ; \
    done ; \
    strip -s --strip-debug /opt/vdr/bin/vdr

# REMOVE DOCS & LOCALES
RUN rm -Rf /opt/vdr/man
RUN rm -Rf /opt/vdr/locale/*

# REMOVE UNUSED PLUGINS
ENV LIBS="dvbhddevice dvbsddevice epgtableid0 hello osddemo pictures rcu skincurses status svccli svcsvr svdrpdemo streamdev-client"
RUN for lib in ${LIBS} ; do \
    echo "removing /opt/vdr/lib/libvdr-$lib" ; \
        rm -f /opt/vdr/lib/libvdr-${lib}* ; \
    done

#####################################################################
# BUILD VDR IMAGE
#####################################################################
FROM alpine:3.8 AS vdr-server

USER root

# INSTALL DEPENDENCIES
RUN apk update && \
    apk add freetype fontconfig libintl libexecinfo libjpeg-turbo libcap pugixml libcurl \
        libcrypto1.0 pcre-dev imagemagick-dev dcron wget curl bash perl perl-date-manip \
        apache2 php7-apache2 php7-openssl tzdata && \
    rm -rf /var/cache/apk/*

# CREATE DIRS
RUN mkdir -p /opt && \
    mkdir -p /data && \
    mkdir -p /video && \
    mkdir -p /opt/templates/ \
    mkdir -p /timeshift

# COPY BINARIES
COPY --from=vdr-build /opt/ /opt/
COPY --from=vdr-build /usr/local/lib/ /usr/local/lib/

# COPY TEMPLATES
ADD templates/vdr/ /opt/templates/vdr/
ADD templates/web/ /opt/templates/web/
COPY templates/webgrab/WebGrab++.config.xml /webgrab/
COPY templates/xmltv2vdr/* /xmltv2vdr/

# MODIFY APACHE CONFIG
RUN mkdir /run/apache2 \
    && sed -i "s/#LoadModule\ rewrite_module/LoadModule\ rewrite_module/" /etc/apache2/httpd.conf \
    && sed -i "s/#LoadModule\ session_module/LoadModule\ session_module/" /etc/apache2/httpd.conf \
    && sed -i "s/#LoadModule\ session_cookie_module/LoadModule\ session_cookie_module/" /etc/apache2/httpd.conf \
    && sed -i "s/#LoadModule\ session_crypto_module/LoadModule\ session_crypto_module/" /etc/apache2/httpd.conf \
    && sed -i "s/#LoadModule\ deflate_module/LoadModule\ deflate_module/" /etc/apache2/httpd.conf \
    && sed -i "s#^DocumentRoot \".*#DocumentRoot \"/data/web\"#g" /etc/apache2/httpd.conf \
    && sed -i "s#/var/www/localhost/htdocs#/data/web#" /etc/apache2/httpd.conf \
    && sed -i -e 's/Listen 80/Listen 8099/g' /etc/apache2/httpd.conf \
    && printf "\n<Directory \"/app/public\">\n\tAllowOverride All\n</Directory>\n" >> /etc/apache2/httpd.conf

# SET DEFAULT ENVIRONMENT VARIABLES
ENV DVBAPI_ENABLE="1" \
    DVBAPI_HOST="192.168.242.40" \
    DVBAPI_PORT="2041" \
    DVBAPI_OFFSET="0" \
    SATIP_NUMDEVICES="4" \
    SATIP_SERVER=192.168.242.43|DVBC-8|OctopusNet \
    ROBOTV_TIMESHIFTDIR="/video" \
    ROBOTV_MAXTIMESHIFTSIZE="4000000000" \
    ROBOTV_PICONSURL="http://192.168.242.40/iptv/picons" \
    ROBOTV_SERIESFOLDER="Serien" \
    ROBOTV_EPGIMAGEURL= \
    VDR_LOGLEVEL="2" \
    VDR_UPDATECHANNELS="3" \
    TZ="Europe/Berlin"

# EXPOSE PORTS
EXPOSE 8099

# SET RUNSCRIPT
COPY bin/run.sh /opt/vdr/
RUN chmod +x /opt/vdr/run.sh

# RUN VDR
ENTRYPOINT [ "/opt/vdr/run.sh" ]
