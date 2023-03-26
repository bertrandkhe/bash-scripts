#!/bin/bash

# set -ux;

Help() {
	echo "Setup outline ss server on Aliyun ECS"
	echo
	echo "Syntax: ./setup-outline.sh -s sender@example.com -r receiver@example.com"
	echo "Mandatory options:"
	echo "s		Email address to send notification for new key"
	echo "r		Email address to receive notification for new key"
}

sender_address=""
receiver_address=""

while getopts ":hs:r:" option; do
	case $option in
		h)
			Help
			exit;;
		s)
			sender_address="$OPTARG";;
		r)
			receiver_address="$OPTARG";;
		?)
			echo "Invalid option $option"
			exit 1;;
	esac
done

if [[ $sender_address = "" ]] || [[ $receiver_address = "" ]]; then
	echo "Missing sender email address or/and receiver email address."
	echo
	Help
	exit 1
fi

sudo apt-get update

has_curl="$(which curl)"
has_jq="$(which jq)"
has_git="$(which git)"

if [[ "$has_curl" = ""  ]]; then
	sudo apt-get install -y curl
fi

if [[ "$has_jq" = ""  ]]; then
	sudo apt-get install -y jq
fi

if [[ "$has_git" = ""  ]]; then
	sudo apt-get install -y git
fi

# Aliyun CLI is used to send notifications

# Download aliyun cli
has_aliyun="$(which aliyun)"
if [[ "$has_aliyun" = "" ]]; then
	version="$(curl https://api.github.com/repos/aliyun/aliyun-cli/releases/latest | jq -r .tag_name)"
	curl -L "https://github.com/aliyun/aliyun-cli/releases/download/$version/aliyun-cli-linux-${version:1}-amd64.tgz" -o /tmp/aliyun.tgz
	sudo tar xf /tmp/aliyun.tgz -C /usr/local/bin/
fi

# Setup aliyun config
if [[ ! -f "~/.aliyun/config.json" ]]; then
	ram_role="$(curl http://100.100.100.200/latest/meta-data/ram/security-credentials/)"
	if [[ $ram_role = "" ]]; then
		echo "RAM role not found. You need to attach a RAM role to this instance. This RAM role must have the permission AliyunDirectMailFullAccess."
	fi
	region_id="$(curl http://100.100.100.200/latest/meta-data/region-id)"
	mkdir -p ~/.aliyun
	cat <<EOF > ~/.aliyun/config.json
{
	"current": "default",
	"profiles": [
		{
			"name": "default",
			"mode": "EcsRamRole",
			"ram_role_name": "$ram_role",
			"region_id": "$region_id",
			"output_format": "json",
			"language": "en"
		}
	],
	"meta_path": ""
}
EOF

fi

# Download outline-ss-server
user_id="$(id -u)"
group_id="$(id -g)"
if [[ ! -d /opt/outline ]]; then
	sudo mkdir -p /opt/outline
	sudo chown $user_id:$group_id /opt/outline
fi
version="$(curl https://api.github.com/repos/Jigsaw-Code/outline-ss-server/releases/latest | jq -r .tag_name)"
if [ ! -f "/opt/outline/version" ]; then
	touch /opt/outline/version;
fi
installed_version="$(cat /opt/outline/version)"

if [[ "$version" != "$installed_version" ]]; then
	curl -L \
		"https://github.com/Jigsaw-Code/outline-ss-server/releases/download/$version/outline-ss-server_${version:1}_linux_x86_64.tar.gz" \
	   	-o /tmp/outline-ss-server.tar.gz
	tar xf /tmp/outline-ss-server.tar.gz -C /opt/outline
	sudo chown -R $user_id:$group_id /opt/outline
	sudo ln -s /opt/outline/outline-ss-server /usr/local/bin
fi
echo $version > /opt/outline/version

# Generate outline start script
etc_dir=/etc/outline
username="$(whoami | xargs echo -n)"
port=8080
# Only use one of these ciphers as of March 2023:
# - chacha20-ietf-poly1305
# - aes-128-gcm, aes-256-gcm
# Explanation here: 
# - https://nordpass.com/blog/xchacha20-encryption-vs-aes-256/
# - https://github.com/shadowsocks/shadowsocks-rust#supported-ciphers
# - https://github.com/Jigsaw-Code/outline-server#shadowsocks-resistance-against-detection-and-blocking
# Check outline-server and shadowsocks-rust repositories on Github to see if cipher have to be updated.
cipher="chacha20-ietf-poly1305"

cat <<EOF > /opt/outline/start.sh
#!/bin/bash
secret="\$(openssl rand -base64 16)"

sudo mkdir -p $etc_dir
sudo chown -R $user_id:$group_id $etc_dir
cat > $etc_dir/config.yml <<CEOF
keys:
    - id: $username
      port: $port
      cipher: $cipher
      secret: "\$secret"
CEOF

# Fetch ECS metadata
# https://www.alibabacloud.com/help/en/elastic-compute-service/latest/overview-of-ecs-instance-metadata
eipv4="\$(curl http://100.100.100.200/latest/meta-data/eipv4)"
auth="$cipher:\$secret"
# Generate key with prefix. Read more here:
# - https://github.com/Jigsaw-Code/outline-client/pull/1454
# - https://geneva.cs.umd.edu/posts/iran-whitelister/
ssKey="ss://\$(echo -n "\$auth" | base64)@\$eipv4:$port/?outline=1&prefix=%16%03%01%02%00#\$(hostname)-\$(date +"%d-%m-%Y")"
echo -n \$ssKey > $etc_dir/key.txt

now="\$(date +"%Y-%m-%d %H:%M:%S")"
aliyun dm SingleSendMail \\
    --AccountName $sender_address \\
    --AddressType 1 \\
    --ReplyToAddress false \\
    --Subject "[\$now] New key" \\
    --ToAddress $receiver_address \\
    --TextBody "Hello, here is the new key: \$ssKey"

outline-ss-server --config=$etc_dir/config.yml --replay_history=20000
EOF
chmod +x /opt/outline/start.sh


# Create, enable and start outline service
service_path="/etc/systemd/system/outline-ss-server.service"
if [[ ! -f $service_path  ]]; then
	cat << EOF > /tmp/outline-ss-server.service
[Unit]
Description=Outline service
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=2
User=$username
ExecStart=/opt/outline/start.sh

[Install]
WantedBy=multi-user.target
EOF
	sudo mv /tmp/outline-ss-server.service $service_path
fi

sudo systemctl enable outline-ss-server.service
sudo systemctl restart outline-ss-server.service
