#!/usr/bin/env bash

# Deploy script Zabbix Agent for Debian v1.0

source "$(dirname "$0")/ft-util/ft-util_inc_var"

SRC_DIR="/usr/local/src"
PKG_REPO_URL="repo.zabbix.com/zabbix/5.0/debian"
PKG_ZBX_URL="https://${PKG_REPO_URL}/pool/main/z/zabbix-release"
PKG_ZBX_NAME="zabbix-release_5.0-1"
ZBX_CONF="/etc/zabbix/zabbix_agentd.conf"

#############################
#############################
## LOAD PARAMETERS
#############################
#############################

if [ -n "$1" ] && [ -n "$2" ]
then
    ZBX_SRV_PASSIVE=$1
    ZBX_SRV_ACTIVE=$2
else
    $S_LOG -s crit -d $S_NAME "You need to give \"zabbix_passive_server_name,zabbix_passive_server_ip\" \"zabbix_active_server_name\" "
    exit 1
fi

$S_LOG -d $S_NAME "Start $S_NAME $*"

#############################
#############################
## REMOVE ZABBIX
#############################
#############################

$S_LOG -d $S_NAME "Removing zabbix-agent"
echo "#################################################################################"
echo "#################################################################################"
apt-get remove --yes --purge zabbix-agent -y
echo "#################################################################################"
echo "#################################################################################"
dpkg -r zabbix-release
echo "#################################################################################"
echo "#################################################################################"

#############################
#############################
## GET CORRECT PACKAGE
#############################
#############################

case $(sed -rn 's/([0-9]+)\.[0-9]+/\1/p' /etc/debian_version) in
    7)
        PKG_REPO_URL="repo.zabbix.com/zabbix/3.0/debian" # Overide for Debian 7
        PKG_ZBX_URL="http://${PKG_REPO_URL}/pool/main/z/zabbix-release"
        PKG_ZBX_NAME="zabbix-release_3.0-2+wheezy_all.deb"
        ;;
    8)  
        PKG_ZBX_NAME="${PKG_ZBX_NAME}+jessie_all.deb"
        ;;
    9)  
        PKG_ZBX_NAME="${PKG_ZBX_NAME}+stretch_all.deb"
        ;;
    10) 
        PKG_ZBX_NAME="${PKG_ZBX_NAME}+buster_all.deb"
        ;;
    *) 
        $S_LOG -s warn -d $S_NAME "Version of Debian not supported by the script."
        exit 1 
        ;;
esac

cd $SRC_DIR
if [ -e ${PKG_ZBX_NAME} ]
then
    $S_LOG -s $? -d $S_NAME "Package ${PKG_ZBX_NAME} found in $SRC_DIR"
else
    wget --quiet ${PKG_ZBX_URL}/${PKG_ZBX_NAME}
    $S_LOG -s $? -d $S_NAME "Download of ${PKG_ZBX_URL}/${PKG_ZBX_NAME} returned code $?"
fi


#############################
#############################
## INSTALL PACKAGES
#############################
#############################

echo "#################################################################################"
echo "#################################################################################"
dpkg -i ${PKG_ZBX_NAME}
$S_LOG -s $? -d $S_NAME "DPKG of ${PKG_ZBX_NAME} returned code $?"
echo "#################################################################################"
echo "#################################################################################"

apt-get update
$S_LOG -s $? -d $S_NAME "APT UPDATE returned code $?"
echo "#################################################################################"
echo "#################################################################################"

apt-get --yes install zabbix-agent
$S_LOG -s $? -d $S_NAME "APT INSTALL of zabbix-agent returned code $?"
echo "############################################################"
echo "############################################################"


#############################
#############################
## EDIT CONFIG FILE
#############################
#############################

$S_LOG -d $S_NAME "==============================================================================="
$S_LOG -d $S_NAME "==============================================================================="

sed -i -r "s/^(Hostname=Zabbix server)/Hostname=$(hostname -f)/g" $ZBX_CONF
$S_LOG -s $? -d $S_NAME "Edited: $(egrep ^Hostname= $ZBX_CONF)"

sed -i -r 's/^(\# HostMetadataItem=)/HostMetadataItem=system.uname/g' $ZBX_CONF
$S_LOG -s $? -d $S_NAME "Edited: $(egrep ^HostMetadataItem= $ZBX_CONF)"

sed -i -r "s/^(Server=127\.0\.0\.1)/Server=$ZBX_SRV_PASSIVE/g" $ZBX_CONF
$S_LOG -s $? -d $S_NAME "Edited: $(egrep ^Server= $ZBX_CONF)"

sed -i -r "s/^(ServerActive=127\.0\.0\.1)/ServerActive=$ZBX_SRV_ACTIVE/g" $ZBX_CONF
$S_LOG -s $? -d $S_NAME "Edited: $(egrep ^ServerActive= $ZBX_CONF)"

$S_LOG -d $S_NAME "==============================================================================="
$S_LOG -d $S_NAME "==============================================================================="

#############################
#############################
## ENABLE ZABBIX SERVICE
#############################
#############################

systemctl enable zabbix-agent &>/dev/null
$S_LOG -s $? -d $S_NAME "systemctl enable zabbix-agent returned code $?" # for Debian 7 it will not work but the agent seems to install itself in /etc/rc2.d/

service zabbix-agent restart &>/dev/null
$S_LOG -s $? -d $S_NAME "service zabbix-agent restart returned code $?"

$S_LOG -d "$S_NAME" "End $S_NAME"