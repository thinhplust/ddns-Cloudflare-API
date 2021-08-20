#!/usr/bin/env bash
export PATH=/sbin:/opt/bin:/usr/local/bin:/usr/contrib/bin:/bin:/usr/bin:/usr/sbin:/usr/bin/X11

## A bash script to update a Cloudflare DNS A record with the External or Internal IP of the source machine ##
## DNS record MUST pre-creating on Cloudflare

##### Config Params
what_ip="external"              ##### Which IP should be used for the record: internal/external
what_interface="enp4s0f0"           ##### For internal IP, provide interface name
dns_record="tv.lungmat.net"   ##### DNS A record which will be updated
zoneid="91dd42ff9ae466578dd962a90a64fde7"               ##### Cloudflare's Zone ID
proxied="false"                 ##### Use Cloudflare proxy on dns record true/false
ttl=120                         ##### 120-7200 in seconds or 1 for Auto
cloudflare_api_token="6411ae804868705ed0e8d2e2adeec6cc10f63" ##### Cloudflare API Token keep it private!!!!
notify_me="no"                  ##### yes/no (yes requires mailutils package installed/configured)
notify_email="thinhplust@gmail.com"    ##### enter your email address (email is only sent if DNS is updated)

##### .updateDNS.log file of the last run for debug
parent_path="$(dirname "${BASH_SOURCE[0]}")"
FILE=${parent_path}/.updateDNS.log
if ! [ -x "$FILE" ]; then
    touch "$FILE"
fi

LOG_FILE=${parent_path}'/.updateDNS.log' #log file name
exec > >(tee $LOG_FILE) 2>&1             # Writes STDOUT & STDERR as log file and prints to screen
echo "==> $(date "+%Y-%m-%d %H:%M:%S")"

##### Get the current IP addresss
if [ "${what_ip}" == "external" ]; then
    ip=$(curl -s -X GET https://checkip.amazonaws.com)
else
    if [ "${what_ip}" == "internal" ]; then
        if which ip >/dev/null; then
            ip=$(ip -o -4 addr show ${what_interface} scope global | awk '{print $4;}' | cut -d/ -f 1)
        else
            ip=$(ifconfig ${what_interface} | grep 'inet ' | awk '{print $2}')
        fi
    else
        echo "missing or incorrect what_ip/what_interface parameter"
    fi
fi

echo "==> Current IP is $ip"

##### get the dns record id and current ip from cloudflare's api
dns_record_info=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records?name=$dns_record" \
    -H "X-Auth-Email: $notify_email" \
    -H "X-Auth-Key: $cloudflare_api_token" \
    -H "Content-Type: application/json")

dns_record_id=$(echo ${dns_record_info} | grep -o '"id":"[^"]*' | cut -d'"' -f4)
dns_record_ip=$(echo ${dns_record_info} | grep -o '"content":"[^"]*' | cut -d'"' -f4)

if [ ${dns_record_ip} == ${ip} ]; then
    echo "==> No changes needed! DNS Recored currently is set to $dns_record_ip"
    exit
else
    echo "==> DNS Record currently is set to $dns_record_ip". Updating!!!
fi

##### updates the dns record
update=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records/$dns_record_id" \
    -H "X-Auth-Email: $notify_email" \
    -H "X-Auth-Key: $cloudflare_api_token" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"$dns_record\",\"content\":\"$ip\",\"ttl\":$ttl,\"proxied\":$proxied}")

if [[ ${update} == *"\"success\":false"* ]]; then
    echo -e "==> FAILED:\n$update"
    exit 1
else
    echo "==> $dns_record DNS Record Updated To: $ip"
    if [ ${notify_me} != "no" ]; then
        mail -s "ip address changed & DNS updated" ${notify_email} </usr/local/bin/.updateDNS.log
        echo "diffrent then no"
    fi
fi
