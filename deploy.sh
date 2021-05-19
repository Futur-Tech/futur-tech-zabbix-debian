#!/usr/bin/env bash

# Deploy script Zabbix Agent for Debian v1.0

source "$(dirname "$0")/ft-util/ft_util_inc_var"

SRC_DIR="/usr/local/src"
PKG_REPO_URL="repo.zabbix.com/zabbix/5.0/debian"
PKG_ZBX_URL="https://${PKG_REPO_URL}/pool/main/z/zabbix-release"
PKG_ZBX_NAME="zabbix-release_5.0-1"
ETC_ZBX="/etc/zabbix"
ZBX_CONF="${ETC_ZBX}/zabbix_agentd.conf"
ZBX_CONF_D="${ETC_ZBX}/zabbix_agentd.conf.d"

LOG_DEBUG=true

$S_LOG -d $S_NAME "Start $S_NAME $*"

if $S_DIR_PATH/ft-util/ft_util_pkg "zabbix-agent"
then
    $S_LOG -d $S_NAME "Zabbix Agent is already installed"

else

    #############################
    ## GET CORRECT PACKAGE     ##
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
    ## REMOVE ZABBIX           ##
    #############################
    $S_LOG -d $S_NAME "Removing zabbix-agent"

    DEBIAN_FRONTEND=noninteractive apt-get remove -qq --purge zabbix-agent < /dev/null > /dev/null
    $S_LOG -s $? -d $S_NAME "apt-get remove -qq --purge zabbix-agent"

    dpkg -r zabbix-release > /dev/null
    $S_LOG -s $? -d $S_NAME "dpkg -r zabbix-release"

    #############################
    ## INSTALL PACKAGES        ##
    #############################

    dpkg -i ${PKG_ZBX_NAME} > /dev/null
    $S_LOG -s $? -d $S_NAME "DPKG of ${PKG_ZBX_NAME} returned code $?"

    $S_DIR_PATH/ft-util/ft_util_pkg -i "zabbix-agent" || exit 1

fi

#############################
## DEPLOY CONFIG FILE      ## 
#############################
$S_LOG -d $S_NAME "Zabbix Agent configuration"

if [ -n "$1" ] && [ -n "$2" ]
then
    ZBX_SRV_PASSIVE=$1
    ZBX_SRV_ACTIVE=$2
else
    source <(grep "Server" ${ZBX_CONF})
    $S_LOG -s $? -d $S_NAME "Loaded ZBX_SRV_PASSIVE and ZBX_SRV_ACTIVE variable from ${ZBX_CONF}"
    ZBX_SRV_PASSIVE="${Server}"
    ZBX_SRV_ACTIVE="${ServerActive}"
    $S_LOG -d $S_NAME "ZBX_SRV_PASSIVE=\"${ZBX_SRV_PASSIVE}\""
    $S_LOG -d $S_NAME "ZBX_SRV_ACTIVE=\"${ZBX_SRV_ACTIVE}\""
fi

[ ! -e "${ZBX_CONF}.origin" ] && cp "${ZBX_CONF}" "${ZBX_CONF}.origin"
mkdir -pv ${ZBX_CONF_D} | $S_LOG -d "$S_NAME" -d "$ZBX_CONF_D" -i

echo "Hostname=$(hostname -f)
Server=${ZBX_SRV_PASSIVE}
ServerActive=${ZBX_SRV_ACTIVE}
PidFile=/var/run/zabbix/zabbix_agentd.pid
LogFile=/var/log/zabbix/zabbix_agentd.log
Include=${ZBX_CONF_D}/*.conf" > ${ZBX_CONF}
cat $ZBX_CONF | $S_LOG -d "$S_NAME" -d "$ZBX_CONF" -i 

#############################
## ENABLE ZABBIX SERVICE   ##
#############################
systemctl enable zabbix-agent &>/dev/null
$S_LOG -s $? -d $S_NAME "systemctl enable zabbix-agent returned code $?" # for Debian 7 it will not work but the agent seems to install itself in /etc/rc2.d/

#############################
## RESTART ZABBIX SERVICE  ##
#############################
echo "service zabbix-agent restart" | at now + 1 min &>/dev/null ## restart zabbix agent with a delay
$S_LOG -s $? -d "$S_NAME" "Scheduling Zabbix Agent Restart"

$S_LOG -d "$S_NAME" "End $S_NAME"