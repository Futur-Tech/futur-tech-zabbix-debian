# Futur-Tech Zabbix Agent Deploy for Debian

For Debian 8-9-10, Zabbix Agent 5.0 will be installed.
 
For Debian 7, Zabbix Agent 3.0 will be installed.

    ./deploy.sh "zabbix_passive_server_name,zabbix_passive_server_ip" "zabbix_active_server_name"
  

## deploy-update.sh
  
    ./deploy-update.sh -b main
    
This script will automatically pull the latest version of the branch ("main" in the example) and relaunch itself if a new version is found. Then it will run deploy.sh. Also note that any additional arguments given to this script will be passed to the deploy.sh script.
