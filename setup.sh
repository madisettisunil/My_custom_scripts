#!/bin/bash

if [[ $EUID -ne 0 ]]; then
	echo "Please run this script as root" 1>&2
	exit 1
fi

### Functions ###

function ubuntu_initialize() {
	echo "Updating distribution, installing git,disabling ipv6 and changing hostname"
	apt-get -qq update > /dev/null 2>&1
	apt-get install -qq -y git > /dev/null 2>&1

	update-rc.d nfs-common disable > /dev/null 2>&1
	update-rc.d rpcbind disable > /dev/null 2>&1

	echo "IPv6 Disabled"

	cat <<-EOF >> /etc/sysctl.conf
	net.ipv6.conf.all.disable_ipv6 = 1
	net.ipv6.conf.default.disable_ipv6 = 1
	net.ipv6.conf.lo.disable_ipv6 = 1
	net.ipv6.conf.eth0.disable_ipv6 = 1
	net.ipv6.conf.eth1.disable_ipv6 = 1
	net.ipv6.conf.ppp0.disable_ipv6 = 1
	net.ipv6.conf.tun0.disable_ipv6 = 1
	EOF

	sysctl -p > /dev/null 2>&1

	echo "Changing Hostname"

	read -p "Enter your hostname: " -r primary_domain

	cat <<-EOF > /etc/hosts
	127.0.1.1 $primary_domain $primary_domain
	127.0.0.1 localhost
	EOF

	cat <<-EOF > /etc/hostname
	$primary_domain
	EOF

	echo "The System will now reboot!"
	reboot
}


function reset_firewall() {
	apt-get install iptables-persistent -q -y > /dev/null 2>&1

	iptables -F
	echo "Current iptables rules flushed"
	cat <<-ENDOFRULES > /etc/iptables/rules.v4
	*filter
	# Allow all loopback (lo) traffic and reject anything to localhost that does not originate from lo.
	-A INPUT -i lo -j ACCEPT
	-A INPUT ! -i lo -s 127.0.0.0/8 -j REJECT
	-A OUTPUT -o lo -j ACCEPT
	# Allow ping and ICMP error returns.
	-A INPUT -p icmp -m state --state NEW --icmp-type 8 -j ACCEPT
	-A INPUT -p icmp -m state --state ESTABLISHED,RELATED -j ACCEPT
	-A OUTPUT -p icmp -j ACCEPT
	# Allow SSH.
	-A INPUT -i  eth0 -p tcp -m state --state NEW,ESTABLISHED --dport 22 -j ACCEPT
	-A OUTPUT -o eth0 -p tcp -m state --state NEW,ESTABLISHED --sport 22 -j ACCEPT
	# Allow DNS resolution and limited HTTP/S on eth0.
	# Necessary for updating the server and keeping time.
	-A INPUT  -p udp -m state --state NEW,ESTABLISHED --sport 53 -j ACCEPT
	-A OUTPUT  -p udp -m state --state NEW,ESTABLISHED --dport 53 -j ACCEPT
	-A INPUT  -p tcp -m state --state ESTABLISHED --sport 80 -j ACCEPT
	-A INPUT  -p tcp -m state --state ESTABLISHED --sport 443 -j ACCEPT
	-A OUTPUT  -p tcp -m state --state NEW,ESTABLISHED --dport 80 -j ACCEPT
	-A OUTPUT  -p tcp -m state --state NEW,ESTABLISHED --dport 443 -j ACCEPT
	# Allow Mail Server Traffic outbound
	-A OUTPUT  -p tcp -m state --state NEW,ESTABLISHED --dport 143 -j ACCEPT
	-A OUTPUT  -p tcp -m state --state NEW,ESTABLISHED --dport 587 -j ACCEPT
	-A OUTPUT  -p tcp -m state --state NEW,ESTABLISHED --dport 993 -j ACCEPT
	-A OUTPUT  -p tcp -m state --state NEW,ESTABLISHED --dport 25 -j ACCEPT
	# Allow Mail Server Traffic inbound
	-A INPUT  -p tcp -m state --state NEW,ESTABLISHED --sport 143 -j ACCEPT
	-A INPUT  -p tcp -m state --state NEW,ESTABLISHED --sport 587 -j ACCEPT
	-A INPUT  -p tcp -m state --state NEW,ESTABLISHED --sport 993 -j ACCEPT
	-A INPUT  -p tcp -m state --state NEW,ESTABLISHED --sport 25 -j ACCEPT
	COMMIT
	ENDOFRULES

	iptables -P INPUT DROP
	iptables -P FORWARD DROP
	iptables -P OUTPUT DROP

	cat <<-ENDOFRULES > /etc/iptables/rules.v6
	*filter
	-A INPUT -j DROP
	-A FORWARD -j DROP
	-A OUTPUT -j DROP
	COMMIT
	ENDOFRULES

	echo "Loading new firewall rules"
	iptables-restore /etc/iptables/rules.v4
	ip6tables-restore /etc/iptables/rules.v6
}

function add_firewall_port(){
	read -p "Enter the port you would like opened: " -r port
	iptables -A INPUT -p tcp --dport ${port} -j ACCEPT
	iptables -A OUTPUT -p tcp --sport ${port} -j ACCEPT
	iptables-save
}


function install_ssl_Cert() {
	git clone https://github.com/certbot/certbot.git /opt/letsencrypt > /dev/null 2>&1

	cd /opt/letsencrypt
	letsencryptdomains=()
	end="false"
	i=0
	
	while [ "$end" != "true" ]
	do
		read -p "Enter your server's domain or done to exit: " -r domain
		if [ "$domain" != "done" ]
		then
			letsencryptdomains[$i]=$domain
		else
			end="true"
		fi
		((i++))
	done
	command="./certbot-auto certonly --standalone "
	for i in "${letsencryptdomains[@]}";
		do
			command="$command -d $i"
		done
	command="$command -n --register-unsafely-without-email --agree-tos"
	
	eval $command

}


function get_dns_entries(){
	extip=$(ifconfig|grep 'Link encap\|inet '|awk '!/Loopback|:127./'|tr -s ' '|grep 'inet'|tr ':' ' '|cut -d" " -f4)
	domain=$(ls /etc/opendkim/keys/ | head -1)
	fields=$(echo "${domain}" | tr '.' '\n' | wc -l)
	dkimrecord=$(cut -d '"' -f 2 "/etc/opendkim/keys/${domain}/mail.txt" | tr -d "[:space:]")

	if [[ $fields -eq 2 ]]; then
		cat <<-EOF > dnsentries.txt
		DNS Entries for ${domain}:
		====================================================================
		Namecheap - Enter under Advanced DNS
		Record Type: A
		Host: @
		Value: ${extip}
		TTL: 5 min
		Record Type: TXT
		Host: @
		Value: v=spf1 ip4:${extip} -all
		TTL: 5 min
		Record Type: TXT
		Host: mail._domainkey
		Value: ${dkimrecord}
		TTL: 5 min
		Record Type: TXT
		Host: ._dmarc
		Value: v=DMARC1; p=reject
		TTL: 5 min
		Change Mail Settings to Custom MX and Add New Record
		Record Type: MX
		Host: @
		Value: ${domain}
		Priority: 10
		TTL: 5 min
		EOF
		cat dnsentries.txt
	else
		prefix=$(echo "${domain}" | rev | cut -d '.' -f 3- | rev)
		cat <<-EOF > dnsentries.txt
		DNS Entries for ${domain}:
		====================================================================
		Namecheap - Enter under Advanced DNS
		Record Type: A
		Host: ${prefix}
		Value: ${extip}
		TTL: 5 min
		Record Type: TXT
		Host: ${prefix}
		Value: v=spf1 ip4:${extip} -all
		TTL: 5 min
		Record Type: TXT
		Host: mail._domainkey.${prefix}
		Value: ${dkimrecord}
		TTL: 5 min
		Record Type: TXT
		Host: ._dmarc
		Value: v=DMARC1; p=reject
		TTL: 5 min
		Change Mail Settings to Custom MX and Add New Record
		Record Type: MX
		Host: ${prefix}
		Value: ${domain}
		Priority: 10
		TTL: 5 min
		EOF
		cat dnsentries.txt
	fi

}


function Install_GoPhish {
	apt-get install unzip > /dev/null 2>&1
	wget https://github.com/gophish/gophish/releases/download/v0.4.0/gophish-v0.4-linux-64bit.zip
	unzip gophish-v0.4-linux-64bit.zip
	cd gophish-v0.4-linux-64bit
        sed -i 's/"listen_url" : "127.0.0.1:3333"/"listen_url" : "0.0.0.0:3333"/g' config.json
	read -r -p "Do you want to add an SSL certificate to your GoPhish? [y/N] " response
	case "$response" in
	[yY][eE][sS]|[yY])
        	 read -p "Enter your web server's domain: " -r primary_domain
		 if [ -f "/etc/letsencrypt/live/${primary_domain}/fullchain.pem" ];then
		 	ssl_cert="/etc/letsencrypt/live/${primary_domain}/fullchain.pem"
       		 	ssl_key="/etc/letsencrypt/live/${primary_domain}/privkey.pem"
       		 	cp $ssl_cert ${primary_domain}.crt
        	 	cp $ssl_key ${primary_domain}.key
        	 	sed -i "s/0.0.0.0:80/0.0.0.0:443/g" config.json
        	 	sed -i "s/gophish_admin.crt/${primary_domain}.crt/g" config.json
        	 	sed -i "s/gophish_admin.key/${primary_domain}.key/g" config.json
			sed -i 's/"use_tls" : false/"use_tls" : true/g' config.json
        	 	sed -i "s/example.crt/${primary_domain}.crt/g" config.json
        	 	sed -i "s/example.key/${primary_domain}.key/g" config.json
		 else
			echo "Certificate not found, use Install SSL option first"
		 fi
       		 ;;
    	*)
        	echo "GoPhish installed"
        	;;
	esac
}


function Install_IRedMail {
	echo "Downloading iRedMail"
	wget https://bitbucket.org/zhb/iredmail/downloads/iRedMail-0.9.9.tar.bz2
	tar -xvf iRedMail-0.9.9.tar.bz2
	cd iRedMail-0.9.9/
	chmod +x iRedMail.sh
	echo "Running iRedMail Installer"
	./iRedMail.sh
}

	
	function add_gophish_service () {

	mkdir /var/log/gophish
	mkdir /root/scripts
	touch /etc/init.d/gophish
	git clone https://github.com/madisettisunil/My_custom_scripts.git /root/scripts/
	cp /root/scripts/Gophish\ service /etc/init.d/gophish
	chmod +x /etc/init.d/gophish
	echo " performing cleanup "
	rm -r /root/scripts/
}
	
PS3="Server Setup Script - Pick an option: "
options=("Ubuntu Prep" "Install SSL" "Get DNS Entries" "Install GoPhish" "Install IRedMail" "reset firewall" "add firewall port" "add gophish service daemon")
select opt in "${options[@]}" "Quit"; do

    case "$REPLY" in

    #Prep
    1) ubuntu_initialize;;

		2) install_ssl_Cert;;

		3) get_dns_entries;;

		4) Install_GoPhish;;

		5) Install_IRedMail;;

		6) reset_firewall;;
		
		7) add_firewall_port;;	
		
		8) add_gophish_service;;	

    $(( ${#options[@]}+1 )) ) echo "Goodbye!"; break;;
    *) echo "Invalid option. Try another one.";continue;;

    esac

done
