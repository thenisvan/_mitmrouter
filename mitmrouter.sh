#!/bin/bash

# VARIABLES
BR_IFACE="br0"
WAN_IFACE="end0"
LAN_IFACE="enx000acd265613"

# wifi
WIFI_IFACE="wlan0"
WIFI_SSID="_lab"
WIFI_PASSWORD="iooaishdoiashdoai"

# 'virtual' LAN settings
LAN_IP="192.168.200.1"
LAN_SUBNET="255.255.255.0"
LAN_DHCP_START="192.168.200.10"
LAN_DHCP_END="192.168.200.200"
LAN_DNS_SERVER="1.1.1.1"

# config files
DNSMASQ_CONF="tmp_dnsmasq.conf"
HOSTAPD_CONF="tmp_hostapd.conf"

# SSL mitm proxy port
SSL_PORT=8081
MITMWEB_PORT=8080
BETTERCAP_UI_PORT=8088
BETTERCAP_API_PORT=8089

# Packet capture options
CAPTURE_FILE="capture-$(date +%Y%m%d-%H%M%S).pcap"
CAPTURE_INTERFACE=$BR_IFACE

# Tool options
MITMWEB=0
BETTERCAP=0
CERT_SERVER=0

# remove config files
rm -f $DNSMASQ_CONF
rm -f $HOSTAPD_CONF

# Display usage
function show_usage {
    echo "Usage: $0 <up/down> [options]"
    echo "Options:"
    echo "  capture      - Start packet capture with tcpdump"
    echo "  mitmweb      - Start mitmweb proxy with web interface"
    echo "  bettercap    - Start bettercap with web interface"
    echo "  cert-server  - Start a simple web server to distribute the SSL certificate"
    echo "Example: $0 up capture mitmweb cert-server"
    exit 1
}

# Check dependencies
function check_dependencies {
    echo "== Checking dependencies"
    local missing=0
    
    # Core dependencies
    for cmd in brctl ifconfig hostapd dnsmasq sysctl iptables; do
        if ! command -v $cmd &> /dev/null; then
            echo "ERROR: $cmd is not installed or not in PATH"
            missing=1
        fi
    done
    
    # Optional dependencies based on options
    if [ $CAPTURE -eq 1 ] && ! command -v tcpdump &> /dev/null; then
        echo "ERROR: tcpdump is not installed or not in PATH (required for capture option)"
        missing=1
    fi
    
    if [ $MITMWEB -eq 1 ] && ! command -v mitmweb &> /dev/null; then
        echo "ERROR: mitmweb is not installed or not in PATH (required for mitmweb option)"
        missing=1
    fi
    
    # if [ $BETTERCAP -eq 1 ] && ! command -v bettercap &> /dev/null; then
    #     echo "ERROR: bettercap is not installed or not in PATH (required for bettercap option)"
    #     missing=1
    # fi
    
    if [ $CERT_SERVER -eq 1 ] && ! command -v python3 &> /dev/null; then
        echo "ERROR: python3 is not installed or not in PATH (required for cert-server option)"
        missing=1
    fi
    
    if [ $missing -eq 1 ]; then
        echo "Please install the missing dependencies and try again."
        exit 1
    fi
}

# Check network interfaces
function check_interfaces {
    echo "== Checking network interfaces"
    local missing=0
    
    # Check if WAN interface exists
    if ! ip link show $WAN_IFACE &> /dev/null; then
        echo "ERROR: WAN interface $WAN_IFACE does not exist"
        missing=1
    fi
    
    # Check if LAN interface exists
    if ! ip link show $LAN_IFACE &> /dev/null; then
        echo "ERROR: LAN interface $LAN_IFACE does not exist"
        missing=1
    fi
    
    # Check if WIFI interface exists
    if ! ip link show $WIFI_IFACE &> /dev/null; then
        echo "ERROR: WIFI interface $WIFI_IFACE does not exist"
        missing=1
    fi
    
    if [ $missing -eq 1 ]; then
        echo "Please check your network interface configuration and try again."
        echo "Available interfaces:"
        ip -brief link show
        exit 1
    fi
}

# Check for correct arguments and store the action
ACTION=$1
if [ "$ACTION" != "up" ] && [ "$ACTION" != "down" ]; then
    show_usage
fi

# Parse additional arguments
CAPTURE=0
shift  # Remove first argument (up/down)

while [ $# -gt 0 ]; do
    case "$1" in
        capture)
            CAPTURE=1
            ;;
        mitmweb)
            MITMWEB=1
            ;;
        bettercap)
            BETTERCAP=1
            ;;
        cert-server)
            CERT_SERVER=1
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            ;;
    esac
    shift
done

# Check dependencies
#check_dependencies

# Check network interfaces
check_interfaces

# kill all services that might interfere
echo "== stop router services"
sudo killall wpa_supplicant
sudo killall dnsmasq
sudo killall sslsplit


# reset the network interfaces
echo "== reset all network interfaces"
sudo ifconfig $LAN_IFACE 0.0.0.0
sudo ifconfig $LAN_IFACE down

sudo ifconfig $BR_IFACE 0.0.0.0
sudo ifconfig $BR_IFACE down

sudo ifconfig $WIFI_IFACE 0.0.0.0
sudo ifconfig $WIFI_IFACE down

#sudo brctl delbr $BR_IFACE
sudo ip link show $BR_IFACE &>/dev/null && sudo brctl delbr $BR_IFACE



if [ "$ACTION" = "up" ]; then
    # stop ufw firewall
    sudo systemctl stop ufw

    echo "== create dnsmasq config file"
    echo "interface=${BR_IFACE}" > $DNSMASQ_CONF
    echo "dhcp-range=${LAN_DHCP_START},${LAN_DHCP_END},${LAN_SUBNET},12h" >> $DNSMASQ_CONF
    echo "dhcp-option=6,${LAN_DNS_SERVER}" >> $DNSMASQ_CONF
    echo "no-resolv" >> $DNSMASQ_CONF
    echo "server=1.1.1.1" >> $DNSMASQ_CONF

    echo "create hostapd config file"
    echo "interface=${WIFI_IFACE}" > $HOSTAPD_CONF
    echo "bridge=${BR_IFACE}" >> $HOSTAPD_CONF
    echo "ssid=${WIFI_SSID}" >> $HOSTAPD_CONF
    echo "country_code=US" >> $HOSTAPD_CONF
    echo "hw_mode=g" >> $HOSTAPD_CONF
    echo "channel=11" >> $HOSTAPD_CONF
    echo "wpa=2" >> $HOSTAPD_CONF
    echo "wpa_passphrase=${WIFI_PASSWORD}" >> $HOSTAPD_CONF
    echo "wpa_key_mgmt=WPA-PSK" >> $HOSTAPD_CONF
    echo "wpa_pairwise=CCMP" >> $HOSTAPD_CONF
    echo "ieee80211n=1" >> $HOSTAPD_CONF
    #echo "ieee80211w=1" >> $HOSTAPD_CONF # PMF
    
    echo "== bring up interfaces and bridge"
    sudo ifconfig $WIFI_IFACE up
    sudo ifconfig $WAN_IFACE up
    sudo ifconfig $LAN_IFACE up
    sudo brctl addbr $BR_IFACE
    sudo brctl addif $BR_IFACE $LAN_IFACE
    # Note: hostapd will automatically add WIFI_IFACE to the bridge when it starts
    # because we've specified bridge=$BR_IFACE in the hostapd config
    sudo ifconfig $BR_IFACE up

    # Enable IP forwarding
    echo "== enabling IP forwarding"
    sudo sysctl -w net.ipv4.ip_forward=1
    
    echo "== setup iptables"
    sudo iptables --flush
    sudo iptables -t nat --flush
    sudo iptables -t nat -A POSTROUTING -o $WAN_IFACE -j MASQUERADE
    sudo iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    sudo iptables -A FORWARD -i $BR_IFACE -o $WAN_IFACE -j ACCEPT
    
    # Add SSLsplit redirection rule
    # comment this two lines if you don't want to intercept SSL traffic (you can still view it with WireShark, but encrypted)
    echo "== setting up SSLsplit for traffic interception"
    #sudo iptables -t nat -A PREROUTING -i $BR_IFACE -p tcp --dport 443 -j REDIRECT --to-ports $SSL_PORT
    #sudo iptables -t nat -A PREROUTING -i $BR_IFACE -p tcp --dport 443 -j DNAT --to-destination 192.168.200.100:8080    
    # Add HTTP interception as well
    echo "== setting up HTTP traffic interception"
    #sudo iptables -t nat -A PREROUTING -i $BR_IFACE -p tcp --dport 80 -j REDIRECT --to-ports $SSL_PORT
    #sudo iptables -t nat -A PREROUTING -i $BR_IFACE -p tcp --dport80 -j DNAT --to-destination 192.168.200.100:8080
    
    echo "== setting static IP on bridge interface"
    sudo ifconfig br0 inet $LAN_IP netmask $LAN_SUBNET
    
    # start dnsmasq and hostapd
    echo "== starting dnsmasq"
    sleep 2
    sudo dnsmasq -C $DNSMASQ_CONF

    echo "== starting hostapd"
    sudo hostapd $HOSTAPD_CONF &
    
    # Start SSLsplit if certificates exist
    if [ -f "ca.key" ] && [ -f "ca.crt" ]; then
        echo "== starting SSLsplit for HTTP/HTTPS interception"
        mkdir -p logdir
        sudo sslsplit -D -l connections.log -S logdir/ -k ca.key -c ca.crt \
            http 0.0.0.0 $SSL_PORT \
            https 0.0.0.0 $SSL_PORT &
        echo "== SSLsplit started, logs will be in connections.log and logdir/"
    else
        echo "== WARNING: ca.key and ca.crt not found. Run ./generate_certs.sh to create them."
        echo "== HTTPS interception will not work without certificates!"
    fi

    # Start packet capture if requested
    if [ $CAPTURE -eq 1 ]; then
        echo "== starting packet capture with tcpdump"
        sudo tcpdump -i $CAPTURE_INTERFACE -w $CAPTURE_FILE -C 1000 -W 1000 -Z root &
        echo "== packet capture started, logs will be in $CAPTURE_FILE"
    fi
    
    # Start mitmweb if requested
    if [ $MITMWEB -eq 1 ]; then
        echo "== starting mitmweb proxy"
        mitmweb -k --web-host 0.0.0.0 &
        echo "== mitmweb started, web interface available at http://${LAN_IP}:${MITMWEB_PORT}/"
    fi
    
    # Start bettercap if requested
    if [ $BETTERCAP -eq 1 ]; then
        echo "== starting bettercap"
        bettercap -eval "set ui.address 0.0.0.0; set ui.port ${BETTERCAP_UI_PORT}; set api.rest.port ${BETTERCAP_API_PORT}; set api.rest.address 0.0.0.0; ui on; caplets.update" &
        echo "== bettercap started, web interface available at http://${LAN_IP}:${BETTERCAP_UI_PORT}/"
    fi
    
    # Start certificate server if requested
    if [ $CERT_SERVER -eq 1 ]; then
        if [ -f "ca.crt" ]; then
            echo "== starting certificate distribution server"
            mkdir -p www
            cp ca.crt www/
            
            # Create an HTML page to facilitate certificate installation
            cat > www/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>MITM SSL Certificate Installation</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; line-height: 1.6; }
        .container { max-width: 800px; margin: 0 auto; }
        h1 { color: #333; }
        .instructions { background: #f5f5f5; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .button { display: inline-block; background: #4CAF50; color: white; padding: 10px 20px; 
                 text-decoration: none; border-radius: 5px; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <h1>SSL Certificate Installation</h1>
        <p>To view HTTPS traffic through this network, you need to install the root certificate on your device.</p>
        
        <a class="button" href="ca.crt">Download Certificate</a>
        
        <div class="instructions">
            <h2>Installation Instructions:</h2>
            
            <h3>Android:</h3>
            <ol>
                <li>Download the certificate</li>
                <li>Go to Settings → Security → Encryption & Credentials → Install a certificate → CA certificate</li>
                <li>Select the downloaded certificate file</li>
                <li>Follow the prompts to install it</li>
            </ol>
            
            <h3>iOS:</h3>
            <ol>
                <li>Download the certificate</li>
                <li>Go to Settings → Profile Downloaded (will appear at the top)</li>
                <li>Follow the prompts to install it</li>
                <li>Then go to Settings → General → About → Certificate Trust Settings</li>
                <li>Enable full trust for the certificate</li>
            </ol>
            
            <h3>Windows:</h3>
            <ol>
                <li>Download the certificate</li>
                <li>Double-click the file to open the certificate dialog</li>
                <li>Click "Install Certificate"</li>
                <li>Select "Current User" or "Local Machine"</li>
                <li>Select "Place all certificates in the following store" and choose "Trusted Root Certification Authorities"</li>
                <li>Complete the wizard</li>
            </ol>
            
            <h3>macOS:</h3>
            <ol>
                <li>Download the certificate</li>
                <li>Double-click to open in Keychain Access</li>
                <li>Find the certificate in the "System" keychain</li>
                <li>Double-click it and expand the "Trust" section</li>
                <li>Set "When using this certificate" to "Always Trust"</li>
            </ol>
        </div>
    </div>
</body>
</html>
EOF
            
            # Start a simple Python HTTP server
            cd www
            python3 -m http.server 8000 &> /dev/null &
            cd ..
            echo "== Certificate server started at http://${LAN_IP}:8000/"
            echo "== Users can visit this URL to download and install the certificate"
        else
            echo "== WARNING: ca.crt not found. Run ./generate_certs.sh to create it."
            echo "== Certificate server will not be started."
        fi
    fi
    
    echo "== Router setup complete!"
    echo "== Connect devices to the WiFi network: ${WIFI_SSID}"
    echo "== Password: ${WIFI_PASSWORD}"
else
    # bring down the network
    echo "== bringing down the network and cleaning up"
    sudo killall hostapd
    sudo killall dnsmasq
    sudo killall sslsplit
    sudo ifconfig $BR_IFACE down
    sudo brctl delbr $BR_IFACE
    sudo iptables --flush
    sudo iptables -t nat --flush

    # Stop tools if running
    sudo killall tcpdump
    pkill -f mitmweb
    pkill -f bettercap
    pkill -f "python3 -m http.server 8000"
    
    # start ufw firewall
    sudo systemctl start ufw

    # Stop packet capture if running
    sudo killall tcpdump
fi

