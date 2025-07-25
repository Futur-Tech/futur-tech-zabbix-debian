#!/usr/bin/env bash
source "$(dirname "$0")/ft-util/ft_util_inc_func"
source "$(dirname "$0")/ft-util/ft_util_inc_var"

src_dir="/usr/local/src"
zbx_conf="/etc/zabbix/zabbix_agent2.conf"
zbx_conf_d="/etc/zabbix/zabbix_agent2.d"

# Set the default package repository URL and Zabbix release version
zabbix_release_version="7.0"

zabbix_release_current_status=$(dpkg-query --status zabbix-release 2>/dev/null | awk -F': ' '/^Status:/ {print $2}')

$S_DIR_PATH/ft-util/ft_util_pkg "zabbix-agent2" && zabbix_version_installed=$(zabbix_agent2 -V | grep -oP 'zabbix_agent2 \(Zabbix\) [0-9.]+' | awk '{print $3}')

if [[ "$zabbix_version_installed" == "${zabbix_release_version}."* ]] && [[ "$zabbix_release_current_status" == "install ok installed" ]]; then
    $S_LOG -d $S_NAME "Zabbix Agent 2 is already installed and is on version (${zabbix_version_installed})"

else
    if $S_DIR_PATH/ft-util/ft_util_pkg "zabbix-agent2" && [[ "$zabbix_version_installed" != "${zabbix_release_version}."* ]]; then
        $S_LOG -s warn -d $S_NAME "Zabbix Agent 2 is already installed but is on a different major version (${zabbix_version_installed}). It needs to be replaced by Zabbix Agent2 version ${zabbix_release_version}."
    fi

    if $S_DIR_PATH/ft-util/ft_util_pkg "zabbix-agent"; then
        $S_LOG -s warn -d $S_NAME "Zabbix Agent is already installed and needs to be replaced by Zabbix Agent2"
        $S_LOG -s warn -d $S_NAME "Removing zabbix-agent"

        DEBIAN_FRONTEND=noninteractive apt-get remove -qq --purge zabbix-agent </dev/null >/dev/null
        $S_LOG -s $? -d $S_NAME "apt-get remove -qq --purge zabbix-agent returned EXIT_CODE=$?"
    fi

    # Get the OS data from /etc/os-release
    source /etc/os-release
    os_id="$ID"
    os_version_id="$VERSION_ID"
    os_id_append=""

    case "$os_id" in
    debian)
        case "$(uname -m)" in
        x86_64) os_id_append="" ;;
        aarch64) os_id_append="-arm64" ;;
        *)
            $S_LOG -s crit -d $S_NAME "Unsupported Linux Architecture: $os_id $(uname -m)"
            exit 1
            ;;
        esac

        # Map Debian release versions to corresponding Zabbix package names
        declare -A pkg_zbx_name_map=(
            [9]="zabbix-release_latest+debian9_all.deb"
            [10]="zabbix-release_latest+debian10_all.deb"
            [11]="zabbix-release_latest+debian11_all.deb"
            [12]="zabbix-release_latest+debian12_all.deb"
        )
        ;;

    raspbian)
        $S_LOG -s warn -d $S_NAME "Raspberry Pi OS Detected"

        case "$(uname -m)" in
        aarch64) os_id_append="" ;;
        *)
            $S_LOG -s crit -d $S_NAME "Unsupported Linux Architecture: $os_id $(uname -m)"
            exit 1
            ;;
        esac

        # Map Debian release versions to corresponding Zabbix package names
        declare -A pkg_zbx_name_map=(
            [9]="zabbix-release_${zabbix_release_version}-5+debian9_all.deb"
            [10]="zabbix-release_${zabbix_release_version}-5+debian10_all.deb"
            [11]="zabbix-release_${zabbix_release_version}-5+debian11_all.deb"
        )
        ;;

    *)
        $S_LOG -s crit -d $S_NAME "Unsupported OS: $os_id"
        exit 1
        ;;
    esac

    # Check if the Debian version is supported
    if [ -z "${pkg_zbx_name_map[$os_version_id]}" ]; then
        $S_LOG -s crit -d $S_NAME "Version of Debian not supported by the script."
        exit 1
    fi

    # Remove previous Zabbix release if it exists
    case "$zabbix_release_current_status" in
    "")
        $S_LOG -d $S_NAME "zabbix-release package not found. Proceeding with installation of zabbix-release package."
        ;;
    "install ok installed")
        $S_LOG -d $S_NAME "zabbix-release package status is [${zabbix_release_current_status}]. Proceeding with reinstallation."
        run_cmd_log dpkg --purge zabbix-release
        ;;
    *)
        $S_LOG -s warn -d $S_NAME "zabbix-release package status is [${zabbix_release_current_status}] (should be 'install ok installed'). Proceeding with reinstallation."
        run_cmd_log dpkg --purge zabbix-release
        ;;
    esac

    cd $src_dir
    run_cmd_log find ${src_dir} -type f -name \'zabbix-release_*.deb*\' -print -delete                                                                                         # Delete previous zabbix-release package
    run_cmd_log wget --quiet "https://repo.zabbix.com/zabbix/${zabbix_release_version}/${os_id}${os_id_append}/pool/main/z/zabbix-release/${pkg_zbx_name_map[$os_version_id]}" # Download zabbix-release package
    run_cmd_log dpkg --install --force-confdef "${src_dir}/${pkg_zbx_name_map[$os_version_id]}"                                                                                # Install zabbix-release package
    $S_DIR_PATH/ft-util/ft_util_pkg -u                                                                                                                                         # Update package list
    run_cmd_log apt-get install --quiet --yes -o Dpkg::Options::="--force-confold" zabbix-agent2                                                                               # Install/upgrade Zabbix Agent 2
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

[ ! -e "$zbx_conf.origin" ] && cp $zbx_conf $zbx_conf.origin
mkdir_if_missing $zbx_conf_d
bak_if_exist $zbx_conf

# Migrating PSK config from Zabbix Agent to Zabbix Agent 2
if [ -f "/etc/zabbix/zabbix_agentd.conf.d/ft-psk.conf" ]; then
    $S_LOG -s warn -d $S_NAME "Migrating PSK config to Zabbix Agent 2"
    mv -f "/etc/zabbix/zabbix_agentd.conf.d/ft-psk.conf" "${zbx_conf_d}/ft-psk.conf"
    mv -f "/etc/zabbix/zabbix_agentd.conf.d/ft-psk-userparam.conf" "${zbx_conf_d}/ft-psk-userparam.conf"
fi

mkdir_if_missing "/var/log/zabbix/"
run_cmd_log chown zabbix:zabbix "/var/log/zabbix/"

# Add zabbix user to standard monitoring group https://wiki.debian.org/SystemGroups
run_cmd_log usermod --append --groups adm zabbix
run_cmd_log usermod --append --groups systemd-journal zabbix

echo "# Generated by ${S_NAME}
Hostname=$(hostname -f)
Server=${ZBX_SRV_PASSIVE}
ServerActive=${ZBX_SRV_ACTIVE}
PidFile=/var/run/zabbix/zabbix_agent2.pid
LogFile=/var/log/zabbix/zabbix_agent2.log
LogFileSize=8
ControlSocket=/run/zabbix/agent.sock
PluginSocket=/run/zabbix/agent.plugin.sock
Include=${zbx_conf_d}/*.conf" >${zbx_conf}
cat $zbx_conf | $S_LOG -s debug -d "$S_NAME" -d "$zbx_conf" -i

show_bak_diff_rm $zbx_conf

# Enable Zabbix Agent 2
run_cmd_log systemctl enable zabbix-agent2 &>/dev/null

# Restart Zabbix Agent 2
echo "systemctl restart zabbix-agent2" | at now + 1 min &>/dev/null ## restart zabbix agent with a delay
$S_LOG -s $? -d "$S_NAME" "Scheduling Zabbix Agent Restart"

exit
