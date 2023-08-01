#!/usr/bin/env bash

source "$(dirname "$0")/ft-util/ft_util_inc_func"
source "$(dirname "$0")/ft-util/ft_util_inc_var"

src_dir="/usr/local/src"
zbx_conf="/etc/zabbix/zabbix_agent2.conf"
zbx_conf_d="/etc/zabbix/zabbix_agent2.d"

# Set the default package repository URL and Zabbix release version
zabbix_release_version="6.0"

$S_DIR_PATH/ft-util/ft_util_pkg "zabbix-agent2" && zabbix_version_installed=$(zabbix_agent2 -V | grep -oP 'zabbix_agent2 \(Zabbix\) [0-9.]+' | awk '{print $3}')

if $S_DIR_PATH/ft-util/ft_util_pkg "zabbix-agent2" && [[ "$zabbix_version_installed" == "${zabbix_release_version}."* ]]; then
    $S_LOG -d $S_NAME "Zabbix Agent 2 is already installed and is on version (${zabbix_version_installed})"

else
    if $S_DIR_PATH/ft-util/ft_util_pkg "zabbix-agent2"; then
        $S_LOG -s warn -d $S_NAME "Zabbix Agent 2 is already installed but is on a different major version (${zabbix_version_installed}). It needs to be replaced by Zabbix Agent2 version ${zabbix_release_version}."
    fi

    if $S_DIR_PATH/ft-util/ft_util_pkg "zabbix-agent"; then
        $S_LOG -s warn -d $S_NAME "Zabbix Agent is already installed and needs to be replaced by Zabbix Agent2"
        $S_LOG -s warn -d $S_NAME "Removing zabbix-agent"

        DEBIAN_FRONTEND=noninteractive apt-get remove -qq --purge zabbix-agent </dev/null >/dev/null
        $S_LOG -s $? -d $S_NAME "apt-get remove -qq --purge zabbix-agent returned EXIT_CODE=$?"
    fi

    run_cmd_log dpkg -r zabbix-release

    # Get the Debian version number (major version)
    debian_version=$(sed -rn 's/([0-9]+)\.[0-9]+/\1/p' /etc/debian_version)

    # Check if the Debian version is 12 or above
    if [ "$debian_version" -ge 12 ]; then
        $S_LOG -d $S_NAME "Debian version 12 or above detected. Skipping download of repo."
        [ -e "/etc/apt/sources.list.d/zabbix.list" ] && run_cmd_log rm -f "/etc/apt/sources.list.d/zabbix.list"
        [ -e "/etc/apt/sources.list.d/zabbix.list" ] && run_cmd_log rm -f "/etc/apt/sources.list.d/zabbix.list"

    else

        # Get the ID from /etc/os-release
        source /etc/os-release
        case "$ID" in
        debian)
            # Map Debian release versions to corresponding Zabbix package names
            declare -A pkg_zbx_name_map=(
                [9]="zabbix-release_latest+debian9_all.deb"
                [10]="zabbix-release_latest+debian10_all.deb"
                [11]="zabbix-release_latest+debian11_all.deb"
            )
            ;;

        raspbian)
            $S_LOG -s warn -d $S_NAME "Raspberry Pi OS Detected"

            # Map Debian release versions to corresponding Zabbix package names
            declare -A pkg_zbx_name_map=(
                [9]="zabbix-release_${zabbix_release_version}-5+debian9_all.deb"
                [10]="zabbix-release_${zabbix_release_version}-5+debian10_all.deb"
                [11]="zabbix-release_${zabbix_release_version}-5+debian11_all.deb"
            )
            ;;

        *)
            $S_LOG -s crit -d $S_NAME "Unsupported OS: $ID"
            exit 1
            ;;
        esac

        # Check if the Debian version is supported
        if [ -z "${pkg_zbx_name_map[$debian_version]}" ]; then
            $S_LOG -s crit -d $S_NAME "Version of Debian not supported by the script."
            exit 1
        fi

        cd $src_dir
        run_cmd_log wget --quiet "https://repo.zabbix.com/zabbix/6.0/${ID}/pool/main/z/zabbix-release/${pkg_zbx_name_map[$debian_version]}"

        # Install packages
        run_cmd_log dpkg -i "${src_dir}/${pkg_zbx_name_map[$debian_version]}"
    fi

    # # Remove Zabbix Agent 2 (if was installed)
    # $S_LOG -d $S_NAME "Removing Zabbix Agent 2"
    # DEBIAN_FRONTEND=noninteractive apt-get remove -qq --purge zabbix-agent2 </dev/null >/dev/null
    # $S_LOG -s $? -d $S_NAME "apt-get remove -qq --purge zabbix-agent2"

    # Install Zabbix Agent 2
    $S_DIR_PATH/ft-util/ft_util_pkg -u -i "zabbix-agent2" || exit 1
fi

if [ -n "$1" ] && [ -n "$2" ]; then
    ZBX_SRV_PASSIVE=$1
    ZBX_SRV_ACTIVE=$2
else
    source <(grep "Server" ${zbx_conf})
    $S_LOG -s $? -d $S_NAME "Loaded ZBX_SRV_PASSIVE and ZBX_SRV_ACTIVE variable from ${zbx_conf}"
    ZBX_SRV_PASSIVE="${Server}"
    ZBX_SRV_ACTIVE="${ServerActive}"
fi

[ ! -e "${zbx_conf}.origin" ] && cp "${zbx_conf}" "${zbx_conf}.origin"
[ ! -d "${zbx_conf_d}" ] && run_cmd_log mkdir -pv "${zbx_conf_d}"

# Migrating PSK config from Zabbix Agent to Zabbix Agent 2
if [ -f "/etc/zabbix/zabbix_agentd.conf.d/ft-psk.conf" ]; then
    $S_LOG -s warn -d $S_NAME "Migrating PSK config to Zabbix Agent 2"
    mv -f "/etc/zabbix/zabbix_agentd.conf.d/ft-psk.conf" "${zbx_conf_d}/ft-psk.conf"
    mv -f "/etc/zabbix/zabbix_agentd.conf.d/ft-psk-userparam.conf" "${zbx_conf_d}/ft-psk-userparam.conf"
fi

[ ! -d "/var/log/zabbix/" ] && run_cmd_log mkdir -pv "/var/log/zabbix/"
run_cmd_log chown zabbix:zabbix "/var/log/zabbix/"

# Add zabbix user to standard monitoring group https://wiki.debian.org/SystemGroups
run_cmd_log usermod --append --groups adm zabbix
run_cmd_log usermod --append --groups systemd-journal zabbix

echo "# Generated by ${S_NAME}
# $(date)
Hostname=$(hostname -f)
Server=${ZBX_SRV_PASSIVE}
ServerActive=${ZBX_SRV_ACTIVE}
PidFile=/var/run/zabbix/zabbix_agent2.pid
LogFile=/var/log/zabbix/zabbix_agent2.log
LogFileSize=0
ControlSocket=/tmp/agent.sock
Include=${zbx_conf_d}/*.conf" >${zbx_conf}
cat $zbx_conf | $S_LOG -d "$S_NAME" -d "$zbx_conf" -i

# Enable Zabbix Agent 2
run_cmd_log systemctl enable zabbix-agent2 &>/dev/null

# Restart Zabbix Agent 2
echo "systemctl restart zabbix-agent2" | at now + 1 min &>/dev/null ## restart zabbix agent with a delay
$S_LOG -s $? -d "$S_NAME" "Scheduling Zabbix Agent Restart"
