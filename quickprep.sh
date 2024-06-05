#!/bin/bash

# create schedule to stop port
# $1 port
# $2 valid period. Format should be 99minute/hour/day/month. Cannot over one year.
create_schedule() {
    PORT=$1
    PERIOD=$2

    num=$(echo "$PERIOD" | grep -oE '^[0-9]+')
    unit=$(echo "$PERIOD" | grep -oE 'minute|hour|day|month$')
    if [ -z $num ] || [ -z "$unit" ]; then
        echo "Please input valid period, for example, 30minute, 12hour, 7day, 3month"
        exit 1
    fi
    # endtime cannot be over one year
    begintime=$(date)
    endtime=$(date -d "$begintime $num $unit" '+%Y-%m-%d %H:%M:%S')
    max=$(date -d "$begintime 12 month" '+%Y-%m-%d %H:%M:%S')
    if [ "$endtime" \> "$max" ]; then
        echo "Period is over one year. Please input period less than that"
        exit 1
    fi
    # insert scheduled task
    crontab -l > cron.tmp
    # delete before insert
    sed -i '/quickprep.sh stop '$PORT'/d' cron.tmp
    echo $(date -d "$endtime" '+%M %H %d %m') "*" "bash `dirname "$0"`/quickprep.sh stop $PORT" >> cron.tmp
    crontab cron.tmp
    rm -f cron.tmp

    echo "Port $PORT will expire at $endtime"
    exit 0
}

# Drop stop schedule by port
# $1 port
drop_schedule() {
    PORT=$1

    if crontab -l | grep "quickprep.sh stop $PORT" >/dev/null 2>&1; then
        crontab -l > cron.tmp
        sed -i '/quickprep.sh stop '$PORT'/d' cron.tmp
        crontab cron.tmp
        rm -f cron.tmp

        echo "Stop schedule of Port $PORT is also dropped"
    fi
    exit 0
}

# create service with port and passcode
# $1 port, default 3389
# $2 passcode, default 9527
create_service () {
    # receive paras
    PORT=$([ -n "$1" ] && echo $1 || echo 3389)
    PWD=$([ -n "$2" ] && echo "$2" || echo "9527")
    EXPIRE=$3

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

    # set expire period
    if [ -n "$EXPIRE" ]; then
        schedule_stop $PORT "$EXPIRE"
    else
        echo "ATTENTION: Port $port's expiration time is not setted"
    fi
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

    drop_schedule $PORT
    exit 0
}

# show stauts
# $1~# port. Optional, show all when not given
show_status() {
    if [ -n "$1" ]; then
        ports="$@"
    else
        # get port according with json file name
        ports=`ls /etc/shadowsocks-libev/ | grep "^[0-9]" | rev | cut -d "." -f2- | rev`
        if [ `expr length "${ports[@]}"` -eq 0 ]; then
            echo "No service is in use"
            exit 1
        fi
    fi

    for port in $ports
    do
        # show result
        sudo systemctl status shadowsocks-libev-server@$port.service | awk 'NR==1 || NR ==3 {print}'
        # show schedule if exists
        crontab -l | grep "quickprep.sh stop $port"
    done
    exit 0
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
