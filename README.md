# ipset-extras
ipset-extras.sh
Originaly proposed by @vgaetera

REFS:
- https://openwrt.org/license
- https://openwrt.org/docs/guide-user/advanced/ipset_extras

====== IP set extras ======
{{section>meta:infobox:howto_links#cli_skills&noheader&nofooter&noeditbutton}}

===== Introduction =====
  * This instruction extends the functionality of [[https://ipset.netfilter.org/|IP sets]].
  * Follow the [[docs:guide-user:advanced:ipset_extras#automated|automated]] section for quick setup.

===== Features =====
  * Create and populate IP sets with domains, CIDRs and ASNs.
  * Populate IP sets automatically at startup.

===== Implementation =====
  * Rely on [[docs:guide-user:base-system:dhcp#ip_sets|UCI configuration]] for IP sets.
  * Process settings with [[https://github.com/openwrt/openwrt/blob/master/package/base-files/files/lib/functions.sh|OpenWrt functions]].
  * Utilize [[https://github.com/openwrt/openwrt/blob/master/package/network/utils/resolveip/src/resolveip.c|resolveip]] to resolve domains.
  * Fetch ASN prefixes using [[https://stat.ripe.net/docs/data_api|RIPEstat Data API]].
  * Use [[docs:guide-user:base-system:hotplug|Hotplug]] to trigger setup automatically.

===== Commands =====
| Sub-command | Description |
| --- | --- |
| ''**setup**'' | Set up IP sets. |
| ''**unset**'' | Unset IP sets. |

===== Instructions =====
```
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
```
  
===== Examples =====
```
# Install packages
opkg update
opkg remove dnsmasq
opkg install dnsmasq-full ipset resolveip

# Configure IP sets, domains, CIDRs and ASNs
uci set dhcp.example="ipset"
uci add_list dhcp.example.name="example"
uci add_list dhcp.example.name="example6"
uci add_list dhcp.example.domain="example.com"
uci add_list dhcp.example.domain="example.net"
uci add_list dhcp.example.cidr="9.9.9.9/32"
uci add_list dhcp.example.cidr="2620:fe::fe/128"
uci add_list dhcp.example.asn="2906"
uci add_list dhcp.example.asn="40027"
uci commit dhcp

# Populate IP sets
ipset setup
```
  
===== Automated =====
```
uclient-fetch -O ipset-extras.sh "https://openwrt.org/_export/code/docs/guide-user/advanced/ipset_extras?codeblock=0"
. ./ipset-extras.sh
```
