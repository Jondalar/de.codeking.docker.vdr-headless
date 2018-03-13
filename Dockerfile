#####################################################################
# COMPILE VDR BUILD
#####################################################################
FROM alpine:edge AS vdr-build
MAINTAINER CodeKing <frank@codeking.de>

ENV ROBOTV_VERSION="master" \
    VDR_VERSION="2.3.8"

USER root

# INSTALL DEPENDENCIES
RUN echo "http://dl-3.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories
RUN apk --update add build-base freetype-dev fontconfig-dev gettext-dev \
	libjpeg-turbo-dev libcap-dev pugixml-dev curl-dev git bzip2 libexecinfo-dev \
	ncurses-dev bash imagemagick-dev pcre-dev openssl-dev zip g++

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

# DOWNLOAD VDR SERVER & PLUGINS
RUN wget ftp://ftp.tvdr.de/vdr/Developer/vdr-$VDR_VERSION.tar.bz2
RUN tar -jxf vdr-$VDR_VERSION.tar.bz2
RUN git clone -b $ROBOTV_VERSION https://github.com/pipelka/vdr-plugin-robotv.git vdr-$VDR_VERSION/PLUGINS/src/robotv
RUN git clone https://github.com/manio/vdr-plugin-dvbapi.git vdr-$VDR_VERSION/PLUGINS/src/dvbapi
RUN git clone https://github.com/vdr-projects/vdr-plugin-epgsearch.git vdr-$VDR_VERSION/PLUGINS/src/epgsearch
RUN git clone -b robotv https://github.com/pipelka/vdr-plugin-satip.git vdr-$VDR_VERSION/PLUGINS/src/satip
RUN git clone https://github.com/vdr-projects/vdr-plugin-streamdev.git vdr-$VDR_VERSION/PLUGINS/src/streamdev
RUN git clone https://github.com/yavdr/vdr-plugin-restfulapi.git vdr-$VDR_VERSION/PLUGINS/src/restfulapi
#RUN git clone https://github.com/vdr-projects/vdr-plugin-live.git vdr-$VDR_VERSION/PLUGINS/src/live
RUN git clone https://github.com/FernetMenta/vdr-plugin-vnsiserver.git vdr-$VDR_VERSION/PLUGINS/src/vnsiserver
RUN git clone https://github.com/flensrocker/vdr-plugin-dummydevice vdr-$VDR_VERSION/PLUGINS/src/dummydevice

WORKDIR vdr-$VDR_VERSION

# COPY TEMPLATE FILES
COPY templates/Make.* /build/vdr-$VDR_VERSION/

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
RUN for plugin in robotv epgsearch dummydevice satip streamdev-server live vnsiserver restfulapi ; do \
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
FROM alpine:edge AS vdr-server

USER root

# INSTALL DEPENDENCIES
RUN echo "http://dl-3.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories
RUN apk update && apk add freetype fontconfig libintl libexecinfo \
    libjpeg-turbo libcap pugixml libcurl libcrypto1.0 pcre-dev imagemagick-dev

# CREATE DIRS
RUN mkdir -p /opt && \
    mkdir -p /data && \
    mkdir -p /video && \
    mkdir -p /opt/templates && \
    mkdir -p /timeshift

# COPY BINARIES
COPY --from=vdr-build /opt/ /opt/
COPY --from=vdr-build /usr/local/lib/ /usr/local/lib/

# COPY TEMPLATES
COPY bin/runvdr.sh /opt/vdr/
COPY templates/diseqc.conf /opt/templates/
COPY templates/sources.conf /opt/templates/
COPY templates/channels.conf /opt/templates/

# SET DEFAULT ENVIRONMENT VARIABLES
ENV DVBAPI_ENABLE="1" \
    DVBAPI_HOST="127.0.0.1" \
    DVBAPI_PORT="2000" \
    DVBAPI_OFFSET=2 \
    SATIP_NUMDEVICES="4" \
    SATIP_SERVER="10.0.0.11|DVBS2-8|OctopusV2" \
    ROBOTV_TIMESHIFTDIR="/video" \
    ROBOTV_MAXTIMESHIFTSIZE="4000000000" \
    ROBOTV_PICONSURL="http://10.0.0.12/picons/" \
    ROBOTV_SERIESFOLDER="Serien" \
    ROBOTV_CHANNELCACHE="true" \
    ROBOTV_EPGIMAGEURL="" \
    VDR_LOGLEVEL="2" \
    VDR_UPDATECHANNELS="3" \
    TZ="Europe/Berlin"

# SET RUNSCRIPT
RUN chmod +x /opt/vdr/runvdr.sh
ENTRYPOINT [ "/opt/vdr/runvdr.sh" ]