#!/bin/sh

# export language
export LANG="en_US.UTF-8"

# configure webserver
WEBDIR=/data/web

mkdir -p ${WEBDIR}/
[ ! -d ${WEBDIR}/epgimages ] && cp -R /opt/templates/web/epgimages ${WEBDIR}/
[ ! -d ${WEBDIR}/picons ] && cp -R /opt/templates/web/picons ${WEBDIR}/

# configure vdr
CONFDIR=/data/etc

mkdir -p ${CONFDIR}/conf.d
echo "0.0.0.0/0" > ${CONFDIR}/svdrphosts.conf 

[ ! -f ${CONFDIR}/channels.conf ] && cp /opt/templates/vdr/channels.conf ${CONFDIR}/
[ ! -f ${CONFDIR}/sources.conf ] && cp /opt/templates/vdr/sources.conf ${CONFDIR}/
[ ! -f ${CONFDIR}/diseqc.conf ] && cp /opt/templates/vdr/diseqc.conf ${CONFDIR}/

# General configuration
echo "UpdateChannels = ${VDR_UPDATECHANNELS}" > ${CONFDIR}/setup.conf
echo "EPGScanTimeout = 0" >> ${CONFDIR}/setup.conf

# DVBAPI configuration
echo "dvbapi.LogLevel = 2" >> ${CONFDIR}/setup.conf
echo "dvbapi.OSCamHost = ${DVBAPI_HOST}" >> ${CONFDIR}/setup.conf
echo "dvbapi.OSCamPort = ${DVBAPI_PORT}" >> ${CONFDIR}/setup.conf

# ENABLE / DISABLE DVBAPI
rm -f ${CONFDIR}/conf.d/40-dvbapi.conf

if [ "${DVBAPI_ENABLE}" = "1" ] ; then 
    echo "[dvbapi]" > ${CONFDIR}/conf.d/40-dvbapi.conf
    echo "-o ${DVBAPI_OFFSET}" >> ${CONFDIR}/conf.d/40-dvbapi.conf
fi

# SATIP configuration
mkdir -p ${CONFDIR}/plugins/satip
echo "[satip]" > ${CONFDIR}/conf.d/50-satip.conf

if [ ! -z "${SATIP_NUMDEVICES}" ] ; then
    echo "-d ${SATIP_NUMDEVICES}" >> ${CONFDIR}/conf.d/50-satip.conf
fi

if [ ! -z "${SATIP_SERVER}" ] ; then
    echo "-s \"${SATIP_SERVER}\"" >> ${CONFDIR}/conf.d/50-satip.conf
fi

echo "satip.EnableEITScan = 0" >> ${CONFDIR}/setup.conf
echo "satip.OperatingMode = 3" >> ${CONFDIR}/setup.conf

# vnsi-server configuration
mkdir -p ${CONFDIR}/plugins/vnsiserver
echo "[vnsiserver]" > ${CONFDIR}/conf.d/50-vnsiserver.conf
echo "0.0.0.0/0" > ${CONFDIR}/plugins/vnsiserver/allowed_hosts.conf

# VDR configuration
echo "[vdr]" > ${CONFDIR}/conf.d/00-vdr.conf
echo "--chartab=ISO-8859-9" >> ${CONFDIR}/conf.d/00-vdr.conf
echo "--port=6419" >> ${CONFDIR}/conf.d/00-vdr.conf
echo "--watchdog=60" >> ${CONFDIR}/conf.d/00-vdr.conf
echo "--log=${VDR_LOGLEVEL}" >> ${CONFDIR}/conf.d/00-vdr.conf

# dummydevice configuration
echo "[dummydevice]" > ${CONFDIR}/conf.d/20-dummydevice.conf

# noEPG configuration
mkdir -p ${CONFDIR}/plugins/noepg
echo "[noepg]" > ${CONFDIR}/conf.d/50-noepg.conf
echo "mode=whitelist" > ${CONFDIR}/plugins/noepg/settings.conf
echo "S19.2E-1-1043-12503 // Eurosport 2 HD Xtra" >> ${CONFDIR}/plugins/noepg/settings.conf

# EPGSearch configuration
echo "[epgsearch]" > ${CONFDIR}/conf.d/50-epgsearch.conf

# restfulapi configuration
[ -f "${CONFDIR}/conf.d/60-restfulapi.conf" ] && rm ${CONFDIR}/conf.d/60-restfulapi.conf
echo "[restfulapi]" > ${CONFDIR}/conf.d/60-restfulapi.conf

# streamdev-server configuration
mkdir -p ${CONFDIR}/plugins/streamdev-server

echo "[streamdev-server]" > ${CONFDIR}/conf.d/50-streamdev-server.conf
echo "0.0.0.0/0" > ${CONFDIR}/plugins/streamdev-server/streamdevhosts.conf
echo "streamdev-server.AllowSuspend = 1" >> ${CONFDIR}/setup.conf
echo "streamdev-server.SuspendMode = 1" >> ${CONFDIR}/setup.conf

# RoboTV configuration
mkdir -p ${CONFDIR}/plugins/robotv
echo "[robotv]" > ${CONFDIR}/conf.d/50-robotv.conf

echo "0.0.0.0/0" > ${CONFDIR}/plugins/robotv/allowed_hosts.conf

echo "TimeShiftDir = ${ROBOTV_TIMESHIFTDIR}" > ${CONFDIR}/plugins/robotv/robotv.conf
echo "MaxTimeShiftSize = ${ROBOTV_MAXTIMESHIFTSIZE}" >> ${CONFDIR}/plugins/robotv/robotv.conf
echo "SeriesFolder = ${ROBOTV_SERIESFOLDER}" >> ${CONFDIR}/plugins/robotv/robotv.conf
echo "ChannelCache = false" >> ${CONFDIR}/plugins/robotv/robotv.conf

if [ ! -z "${ROBOTV_PICONSURL}" ] ; then
    echo "PiconsURL = ${ROBOTV_PICONSURL}" >> ${CONFDIR}/plugins/robotv/robotv.conf
fi

if [ ! -z "${ROBOTV_EPGIMAGEURL}" ] ; then
    echo "EpgImageUrl = ${ROBOTV_EPGIMAGEURL}" >> ${CONFDIR}/plugins/robotv/robotv.conf
fi

# configure vdr
WEBGRABCONFDIR=/data/webgrab

[ ! -f ${WEBGRABCONFDIR}/WebGrab++.config.xml ] && cp /webgrab/WebGrab++.config.xml ${WEBGRABCONFDIR}/
[ ! -d ${WEBGRABCONFDIR}/mdb ] && cp -R /webgrab/mdb/ ${WEBGRABCONFDIR}/
[ ! -d ${WEBGRABCONFDIR}/rex ] && cp -R /webgrab/rex/ ${WEBGRABCONFDIR}/
[ ! -d ${WEBGRABCONFDIR}/siteini.pack ] && cp -R /webgrab/siteini.pack/ ${WEBGRABCONFDIR}/

# run apache
rm -f /run/apache2/apache2.pid
rm -f /run/apache2/httpd.pid

echo "Starting Apache..."
httpd

# run webgrab initially
if [ ! -f /webgrab/guide.xml  ]; then
    (/usr/bin/mono /webgrab/bin/WebGrab+Plus.exe ${WEBGRABCONFDIR}; /xmltv2vdr/xmltv2vdr.pl -c /opt/templates/vdr/channels.conf -x ${WEBGRABCONFDIR}/guide.xml -v) &
fi

# run vd
/opt/vdr/bin/vdr
