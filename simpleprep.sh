#!/bin/bash

# receive paras
PORT=$([ -n "$1" ] && echo $1 || echo 8388)
PWD=$([ -n "$2" ] && echo "$2" || echo "12qwaszx")
AEAD=$([ -n "$3" ] && echo "$3" || echo "chacha20-ietf-poly1305")

# install
if dpkg -s shadowsocks-libev | grep "installed" >/dev/null 2>&1; then
    echo "The shadowsocks-libev already exists"
else
    sudo apt-get update
    sudo apt-get install -y shadowsocks-libev
    if [ $? -eq 0 ]; then
        echo "Finish installing shadowsocks-libev"
    fi
fi
# create conf file
cat << EOF > $PORT.tmp
{
    "server":["::0", "0.0.0.0"],
    "mode":"tcp_and_udp",
    "server_port":$PORT,
    "password":"$PWD",
    "timeout":86400,
    "method":"$AEAD",
    "fast_open":false
}
EOF
sudo mv ./$PORT.tmp /etc/shadowsocks-libev/config.json
# start service
sudo systemctl enable shadowsocks-libev
sudo systemctl restart shadowsocks-libev
sudo systemctl status shadowsocks-libev

echo "Please login with port $PORT and passcode $PWD and AEAD $AEAD"
