# Configure profile
mkdir -p /etc/profile.d
cat << "EOF" > /etc/profile.d/ipset.sh
ipset() {
local IPSET_CMD="${1}"
case "${IPSET_CMD}" in
(setup|unset)
. /lib/functions.sh
config_load dhcp
config_foreach ipset_proc_"${IPSET_CMD}" ipset
uci_commit firewall
/etc/init.d/firewall reload 2> /dev/null ;;
(*) command ipset "${@}" ;;
esac
}

ipset_proc_setup() {
local IPSET_CONF="${1}"
local IPSET_TEMP="$(mktemp -t ipset.XXXXXX)"
{
config_list_foreach "${IPSET_CONF}" domain ipset_domain
config_list_foreach "${IPSET_CONF}" cidr ipset_cidr
config_list_foreach "${IPSET_CONF}" asn ipset_asn
} > "${IPSET_TEMP}"
config_list_foreach "${IPSET_CONF}" name ipset_"${IPSET_CMD}"
rm -f "${IPSET_TEMP}"
}

ipset_proc_unset() {
local IPSET_CONF="${1}"
config_list_foreach "${IPSET_CONF}" name ipset_"${IPSET_CMD}"
}

ipset_setup() {
local IPSET_NAME="${1}"
local IPSET_FAMILY
case "${IPSET_NAME}" in
(*6) IPSET_FAMILY="ipv6" ;;
(*) IPSET_FAMILY="ipv4" ;;
esac
uci -q batch << EOI
set firewall.'${IPSET_NAME}'='ipset'
set firewall.'${IPSET_NAME}'.name='${IPSET_NAME}'
set firewall.'${IPSET_NAME}'.family='${IPSET_FAMILY}'
set firewall.'${IPSET_NAME}'.storage='hash'
set firewall.'${IPSET_NAME}'.match='net'
$(sed -e "/${IPSET_FAMILY/ipv6/\\.}/d
/${IPSET_FAMILY/ipv4/:}/d;s/^.*$/\
del_list firewall.'${IPSET_NAME}'.entry='\0'\n\
add_list firewall.'${IPSET_NAME}'.entry='\0'/" "${IPSET_TEMP}")
EOI
}

ipset_unset() {
local IPSET_NAME="${1}"
uci -q batch << EOI
delete firewall.'${IPSET_NAME}'
EOI
}

ipset_domain() {
local IPSET_ENTRY="${1}"
resolveip "${IPSET_ENTRY}"
}

ipset_cidr() {
local IPSET_ENTRY="${1}"
echo "${IPSET_ENTRY}"
}

ipset_asn() {
local IPSET_ENTRY="${1}"
uclient-fetch -O - "https://stat.ripe.net/data/\
announced-prefixes/data.json?resource=${IPSET_ENTRY}" \
| jsonfilter -e "$['data']['prefixes'][*]['prefix']"
}
EOF
. /etc/profile.d/ipset.sh

# Configure hotplug
mkdir -p /etc/hotplug.d/online
cat << "EOF" > /etc/hotplug.d/online/70-ipset-setup
if [ ! -e /var/lock/ipset-setup ] \
&& lock -n /var/lock/ipset-setup
then . /etc/profile.d/ipset.sh
ipset setup
lock -u /var/lock/ipset-setup
fi
EOF
cat << "EOF" >> /etc/sysupgrade.conf
/etc/hotplug.d/online/70-ipset-setup
EOF
