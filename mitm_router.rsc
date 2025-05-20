# Konfigurácia Mikrotik RouterOS pre MiTM testovaciu stanicu
# Táto konfigurácia vytvára izolovanú IoT sieť s možnosťami MiTM analýzy

# Reset konfigurácie na predvolené hodnoty (odkomentujte ak potrebné)
# /system reset-configuration no-default=yes skip-backup=yes

# Identita systému
/system identity set name=MiTM-Router

# Konfigurácia mostu a VLAN
/interface bridge
add name=bridge comment="Hlavný domáci most"

/interface bridge port
add bridge=bridge interface=ether2 comment="Hlavný domáci port 1"
add bridge=bridge interface=ether3 comment="Port pre IoT zariadenia (príklad)"
add bridge=bridge interface=ether4 comment="Port pre IoT zariadenia (príklad)"
add bridge=bridge interface=wlan1 comment="WiFi rozhranie"

/interface vlan
add interface=bridge vlan-id=10 name=IoT_VLAN comment="Izolovaná VLAN pre IoT zariadenia"

/interface bridge vlan
add bridge=bridge tagged=bridge,ether1 vlan-ids=1 comment="Predvolená VLAN pre hlavnú sieť"
add bridge=bridge tagged=bridge,ether2,wlan1 untagged=ether3,ether4 vlan-ids=10 comment="VLAN 10 pre IoT"

# Konfigurácia IP adries
/ip address
add address=192.168.1.1/24 interface=bridge comment="IP adresa hlavnej siete"
add address=192.168.10.1/24 interface=IoT_VLAN comment="IP adresa IoT siete"

# Konfigurácia DHCP servera
/ip pool
add name=home_pool ranges=192.168.1.100-192.168.1.200 comment="Pool adries pre hlavnú sieť"
add name=iot_pool ranges=192.168.10.100-192.168.10.200 comment="Pool adries pre IoT sieť"

/ip dhcp-server
add name=home_dhcp interface=bridge address-pool=home_pool disabled=no comment="DHCP server pre hlavnú sieť"
add name=iot_dhcp interface=IoT_VLAN address-pool=iot_pool disabled=no comment="DHCP server pre IoT sieť"

/ip dhcp-server network
add address=192.168.1.0/24 gateway=192.168.1.1 dns-server=192.168.1.1 comment="DHCP sieť pre hlavnú sieť"
add address=192.168.10.0/24 gateway=192.168.10.1 dns-server=192.168.10.1,1.1.1.1 comment="DHCP sieť pre IoT sieť"

# Konfigurácia WiFi
/interface wireless security-profiles
add name=iot_security mode=dynamic-keys authentication-types=wpa2-psk wpa2-pre-shared-key="SilneUnikatneHeslo123!" comment="Bezpečnostný profil pre IoT WiFi"

/interface wireless
set [find default=yes] disabled=yes comment="Deaktivovať predvolený WiFi profil"
add name=IoT-Siet ssid=IoT-Siet mode=ap-bridge frequency=auto band=2ghz-b/g/n \
    security-profile=iot_security disabled=no vlan-id=10 \
    vlan-mode=use-tag wps-mode=disabled comment="Samostatná WiFi sieť pre IoT zariadenia"

# Konfigurácia firewallu
/ip firewall address-list
add address=192.168.1.0/24 list=Home_Network comment="Hlavná domáca sieť"
add address=192.168.10.0/24 list=IoT_Network comment="IoT zariadenia"

# NAT a presmerovanie portov pre MiTM
/ip firewall nat
# Presmerovanie HTTP na MiTM proxy
add chain=dstnat action=dst-nat to-addresses=192.168.10.2 to-ports=80 \
    protocol=tcp dst-port=80 src-address-list=IoT_Network comment="Presmerovať HTTP na MiTM proxy"

# Presmerovanie HTTPS na MiTM proxy
add chain=dstnat action=dst-nat to-addresses=192.168.10.2 to-ports=8080 \
    protocol=tcp dst-port=443 src-address-list=IoT_Network comment="Presmerovať HTTPS na MiTM proxy"

# NAT pre IoT sieť
add chain=srcnat action=masquerade src-address-list=IoT_Network out-interface=ether1 comment="NAT pre IoT sieť"

# Pravidlá firewallu
/ip firewall filter
# Povoliť etablované/súvisiace spojenia
add chain=forward action=accept connection-state=established,related comment="Povoliť etablované/súvisiace spojenia"

# Povoliť Home -> IoT (obmedzené)
add chain=forward action=accept src-address-list=Home_Network dst-address-list=IoT_Network \
    protocol=tcp dst-port=80,443,554 comment="Povoliť HTTP, HTTPS, RTSP pre kamery z hlavnej siete"

# Blokovať IoT -> Home
add chain=forward action=drop src-address-list=IoT_Network dst-address-list=Home_Network comment="ZAKÁZAŤ prístup z IoT do hlavnej siete"

# Povoliť IoT -> Internet
add chain=forward action=accept src-address-list=IoT_Network out-interface=ether1 comment="Povoliť IoT zariadeniam prístup na internet"

# Blokovať všetku ostatnú prevádzku Home -> IoT
add chain=forward action=drop src-address-list=Home_Network dst-address-list=IoT_Network comment="Blokovať ostatnú komunikáciu do IoT siete"

# Predvolené zahodenie
add chain=forward action=drop comment="Zahodiť všetku ostatnú prevádzku"

# Uložiť konfiguráciu
/system backup save name=mitm_config_backup 