#!/bin/bash

PORT=$1
PWD=$2
# write config json
cat << EOF > $PORT.tmp
{
    "server":["::0", "0.0.0.0"],
    "mode":"tcp_and_udp",
    "server_port":$PORT,
    "password":"$PWD",
    "timeout":86400,
    "method":"chacha20-ietf-poly1305",
    "fast_open":false
}
EOF
