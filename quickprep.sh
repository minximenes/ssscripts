#!/bin/bash

# create service with port and passcode
# $1 port, default 3389
# $2 passcode, default 9527
create_service () {
    # receive paras
    PORT=$([ -n "$1" ] && echo $1 || echo 3389)
    PWD=$([ -n "$2" ] && echo "$2" || echo "9527")

    # install pkg
    if dpkg -s shadowsocks-libev | grep "installed" >/dev/null 2>&1; then
        echo "The shadowsocks-libev already exists"
    else
        sudo apt-get update
        sudo apt-get install -y shadowsocks-libev=3.3.5+ds-10build3
        if [ $? -eq 0 ]; then
            echo "Finish installing shadowsocks-libev"
            # stop default service
            sudo systemctl disable shadowsocks-libev --now
        fi
    fi
    # call bash to write conf temp file
    bash `dirname "$0"`/write_conf.sh $PORT $PWD
    sudo mv ./$PORT.tmp /etc/shadowsocks-libev/$PORT.json
    # start service
    sudo systemctl enable shadowsocks-libev-server@$PORT.service
    sudo systemctl restart shadowsocks-libev-server@$PORT.service
    # show result(only 1st and 3rd line)
    sudo systemctl status shadowsocks-libev-server@$PORT.service | awk 'NR==1 || NR ==3 {print}'
    echo "Please login with port $PORT and passcode $PWD and AEAD chacha20-ietf-poly1305"
    exit 0
}

# disable service with port
# $1 port
disable_port() {
    PORT=$1
    if [ -z $PORT ]; then
        echo "Please input port number you want to disable"
        exit 1
    fi
    # disable service
    sudo systemctl disable shadowsocks-libev-server@$PORT.service --now
    # remove conf file
    sudo rm /etc/shadowsocks-libev/$PORT.json
    # show result
    sudo systemctl status shadowsocks-libev-server@$PORT.service | awk 'NR==1 || NR ==3 {print}'
    echo "Port $PORT is disabled, the service will disapear after server reboot"
    exit 0
}

# show stauts
# $1~# port. optional, show all when not given
show_status() {
    if [ -n "$1" ]; then
        ports="$@"
    else
        # get port according with json file name
        ports=`ls /etc/shadowsocks-libev/ | grep "^[0-9]" | rev | cut -d "." -f2- | rev`
        if [ `expr length "${ports[@]}"` -eq 0 ]; then
            echo "No service is in use"
        fi
    fi

    for port in $ports
    do
        # show result
        sudo systemctl status shadowsocks-libev-server@$port.service | awk 'NR==1 || NR ==3 {print}'
    done
}

COMD=$1
# shift 1 position and $@ will start from old 2nd para
shift

# only surpport start|restart|stop|status
case "$COMD" in
    start|restart)
        create_service $@
        ;;
    stop)
        disable_port $@
        ;;
    status)
        show_status $@
        ;;
    *)
        echo "Plese input start|restart|stop|status"
        ;;
esac
