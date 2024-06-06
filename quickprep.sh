#!/bin/bash

# add rules by port
# $1 port
add_rules() {
    PORT=$1
    # destination port
    sudo iptables -A SSIN -p tcp --dport $PORT -j ACCEPT
    sudo iptables -A SSIN -p udp --dport $PORT -j ACCEPT
    # source port
    sudo iptables -A SSOUT -p tcp --sport $PORT -j ACCEPT
    sudo iptables -A SSOUT -p udp --sport $PORT -j ACCEPT
}

# delete rules by port
# $1 port
del_rules() {
    PORT=$1
    sudo iptables -D SSIN  -p tcp --dport $PORT -j ACCEPT 2>/dev/null
    sudo iptables -D SSIN  -p udp --dport $PORT -j ACCEPT 2>/dev/null
    sudo iptables -D SSOUT -p tcp --sport $PORT -j ACCEPT 2>/dev/null
    sudo iptables -D SSOUT -p udp --sport $PORT -j ACCEPT 2>/dev/null
}

# create in/out chain by port
# $1 port
# $2 data limit. Format should be 100M/20G
create_data_limt() {
    PORT=$1
    DATA=$2

    num=$(echo "$DATA" | grep -oE '^[0-9]+')
    unit=$(echo "$DATA" | grep -oE 'M|G$')
    if [ -z $num ] || [ -z "$unit" ]; then
        echo "Please input valid data limit, for example, 100M, 20G"
        exit 1
    fi
    case $unit in
        M)
            maxbytes=$num
            ;;
        G)
            maxbytes=$((1024 * num))
            ;;
    esac

    # install pkg
    if ! dpkg -s iptables-persistent >/dev/null 2>&1; then
        sudo apt-get update
        # non interactive
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
        if [ $? -eq 0 ]; then
            echo "Finish installing iptables-persistent"
            # init chain
            sudo iptables -N SSIN
            sudo iptables -N SSOUT
            sudo iptables -A INPUT  -j SSIN
            sudo iptables -A OUTPUT -j SSOUT
        else
            echo "Failed to install iptables-persistent. Please check error message"
            exit 1
        fi
    fi
    # delete before insert
    del_rules $PORT
    # add port rules
    add_rules $PORT
    sudo service netfilter-persistent save >/dev/null

    # create update schedule
    crontab -l > cron.limit.tmp
    # delete before insert
    sed -i '/quickprep.sh updatelimit '$PORT'/d' cron.limit.tmp
    # update every hour
    echo $(date -d "$(date) 1 hour" '+%M %H %d %m') "*" "bash `dirname "$0"`/quickprep.sh updatelimit $PORT $maxbytes/$maxbytes M">> cron.limit.tmp
    crontab cron.limit.tmp
    rm -f cron.limit.tmp

    echo "Port $PORT's data limit: $num$unit"
}

# drop data limit by port
# $1 port
drop_data_limit() {
    PORT=$1

    if crontab -l | grep "quickprep.sh updatelimit $PORT" >/dev/null 2>&1; then
        # delete port rules
        del_rules $PORT
        sudo service netfilter-persistent save >/dev/null

        crontab -l > cron.updatelimit.tmp
        sed -i '/quickprep.sh updatelimit '$PORT'/d' cron.updatelimit.tmp
        crontab cron.updatelimit.tmp
        rm -f cron.updatelimit.tmp

        echo "Data limit of Port $PORT is also dropped"
    fi
}

# create schedule to stop port
# $1 port
# $2 valid period. Format should be 99minute/hour/day/month. Cannot over one year.
create_stop_schedule() {
    PORT=$1
    PERIOD=$2

    num=$(echo "$PERIOD" | grep -oE '^[0-9]+')
    unit=$(echo "$PERIOD" | grep -oE 'minute|hour|day|month$')
    if [ -z $num ] || [ -z "$unit" ]; then
        echo "Please input valid period, for example, 30minute, 12hour, 7day, 3month"
        exit 1
    fi
    # endtime cannot be over one year
    begintime=$(date '+%Y-%m-%d %H:%M:%S')
    endtime=$(date -d "$begintime $num $unit" '+%Y-%m-%d %H:%M:%S')
    max=$(date -d "$begintime 12 month" '+%Y-%m-%d %H:%M:%S')
    if [ "$endtime" \> "$max" ]; then
        echo "Period is over one year. Please input period less than that"
        exit 1
    fi
    # insert scheduled task
    crontab -l > cron.stop.tmp
    # delete before insert
    sed -i '/quickprep.sh stop '$PORT'/d' cron.stop.tmp
    echo $(date -d "$endtime" '+%M %H %d %m') "*" "bash `dirname "$0"`/quickprep.sh stop $PORT" >> cron.stop.tmp
    crontab cron.stop.tmp
    rm -f cron.stop.tmp

    echo "Port $PORT is beginning at $begintime and will expire at $endtime"
}

# Drop stop schedule by port
# $1 port
drop_stop_schedule() {
    PORT=$1

    if crontab -l | grep "quickprep.sh stop $PORT" >/dev/null 2>&1; then
        crontab -l > cron.stop.tmp
        sed -i '/quickprep.sh stop '$PORT'/d' cron.stop.tmp
        crontab cron.stop.tmp
        rm -f cron.stop.tmp

        echo "Stop schedule of Port $PORT is also dropped"
    fi
}

# create service with port and passcode
# $1 port
# -p passcode, default 9527
# -d data limit
# -t time limit for valid period
# -r restart flag. Skip limit setting when restart
create_service() {
    PORT=$1
    if [ -z $PORT ]; then
        echo "Please input port number you want to create"
        exit 1
    fi
    # get options
    PASSCODE=""
    DATA_LIMIT=""
    TIME_LIMIT=""
    RESTART=0
    # only options left in $@, otherwise getopts cannot recognize
    shift
    while getopts :p:d:t:r opt; do
        case $opt in
            p)
                PASSCODE="$OPTARG"
                ;;
            d)
                DATA_LIMIT="$OPTARG"
                ;;
            t)
                TIME_LIMIT="$OPTARG"
                ;;
            r)
                RESTART=1
                ;;
            *)
                echo "Invalid option or arg. Please input again"
                exit 1
                ;;
        esac
    done
    # set default passcode
    if [ -z "$PASSCODE" ]; then
        PASSCODE="9527"
    fi

    # install pkg
    if ! dpkg -s shadowsocks-libev >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y shadowsocks-libev=3.3.5+ds-10build3
        if [ $? -eq 0 ]; then
            echo "Finish installing shadowsocks-libev"
            # stop default service
            sudo systemctl disable shadowsocks-libev --now
        else
            echo "Failed to install shadowsocks-libev. Please check error message"
            exit 1
        fi
    fi
    # call bash to write conf temp file
    bash `dirname "$0"`/write_conf.sh $PORT $PASSCODE
    sudo mv ./$PORT.tmp /etc/shadowsocks-libev/$PORT.json
    # start service
    sudo systemctl enable shadowsocks-libev-server@$PORT.service
    sudo systemctl restart shadowsocks-libev-server@$PORT.service
    # show result(only 1st and 3rd line)
    sudo systemctl status shadowsocks-libev-server@$PORT.service | awk 'NR==1 || NR ==3 {print}'
    echo "Please login with port $PORT and passcode $PASSCODE and AEAD chacha20-ietf-poly1305"

    # skip limit setting when restart
    if [ $RESTART -eq 1 ]; then
        exit 0
    fi
    # set data limit
    if [ -n "$DATA_LIMIT" ]; then
        create_data_limt $PORT "$DATA_LIMIT"
    fi
    # set stop schedule
    if [ -n "$TIME_LIMIT" ]; then
        create_stop_schedule $PORT "$TIME_LIMIT"
    fi
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
    # drop data limit and stop schedule if exists
    drop_data_limit $PORT
    drop_stop_schedule $PORT
}

# update the lastest limit and disable port if limit was over.
# $1 port
# -d left data volume/total data volume
update_data_limit() {
    # calculate the last data usage and update left data valume

    # create next update schedule

    # disable port
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
            exit 0
        fi
    fi
    # usage
    sudo iptables -vn -L SSIN  --line-numbers > in_rules.tmp
    sudo iptables -vn -L SSOUT --line-numbers > out_rules.tmp

    for port in $ports
    do
        # show result
        sudo systemctl status shadowsocks-libev-server@$port.service | awk 'NR==1 || NR ==3 {print}'
        # show usage
        if grep "$port" in_rules.tmp >/dev/null 2>&1; then
            grep -E "num|$port" in_rules.tmp
        fi
        if grep "$port" out_rules.tmp >/dev/null 2>&1; then
            grep -E "num|$port" out_rules.tmp
        fi
        # show data limit and stop schedule if exists
        crontab -l | grep "quickprep.sh updatelimit $port"
        crontab -l | grep "quickprep.sh stop $port"
    done

    rm -f in_rules.tmp out_rules.tmp
}

COMD=$1
# shift 1 position and $@ will start from old 2nd para
shift

# only surpport start|restart|stop|status
case "$COMD" in
    start)
        create_service $@
        ;;
    restart)
        create_service $@ -r
        ;;
    stop)
        disable_port $@
        ;;
    status)
        show_status $@
        ;;
    updatelimit)
        # for inner use
        update_data_limit $@
        ;;
    *)
        echo "Plese input start|restart|stop|status"
        ;;
esac
