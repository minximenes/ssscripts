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
        echo "updating and installing ..."
        sudo apt-get update >/dev/null 2>&1
        # non interactive
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent >/dev/null
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

    # create log
    pdir=`dirname "$0"`
    [ ! -d "$pdir/log" ] && mkdir -p "$pdir/log"
    [ ! -d "$pdir/history" ] && mkdir -p "$pdir/history"
    logfile="$pdir/log/$PORT.log"
    # backup same name file if exists
    mv $logfile $pdir/history/"$PORT"_"$(date '+%Y%m%dT%H%M%S')".log 2>/dev/null
    # init data log
    echo "timestamp tcpin udpin tcpout udpout inout diff usage"> $logfile
    echo "$(date '+%Y%m%dT%H:%M:%S') 0 0 0 0 0 0 0">> $logfile

    # create update schedule
    crontab -l  2>/dev/null > cron.limit.tmp
    # delete before insert
    sed -i '/updateusage '$PORT'/d' cron.limit.tmp
    # update every hours. usage/total(MB)/total
    memo="0/"$maxbytes"M/"$DATA
    echo $(date -d "$(date) 1 hour" '+%M %H %d %m') "*" "bash $pdir/quickprep.sh updateusage $PORT $memo">> cron.limit.tmp
    crontab cron.limit.tmp
    rm -f cron.limit.tmp

    echo "Port $PORT's data limit: $DATA"
}

# drop data limit by port
# $1 port
drop_data_limit() {
    PORT=$1

    if crontab -l 2>/dev/null | grep "updateusage $PORT" >/dev/null; then
        # delete port rules
        del_rules $PORT
        sudo service netfilter-persistent save >/dev/null

        crontab -l > cron.limit.tmp
        sed -i '/updateusage '$PORT'/d' cron.limit.tmp
        crontab cron.limit.tmp
        rm -f cron.limit.tmps

        echo "Data limit of Port $PORT is dropped"
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
    crontab -l  2>/dev/null > cron.stop.tmp
    # delete before insert
    sed -i '/stop '$PORT'/d' cron.stop.tmp
    memo=$(date -d "$begintime" '+%Y-%m-%dT%H:%M:%S')"/"$PERIOD
    echo $(date -d "$endtime" '+%M %H %d %m') "*" "bash `dirname "$0"`/quickprep.sh stop $PORT $memo" >> cron.stop.tmp
    crontab cron.stop.tmp
    rm -f cron.stop.tmp

    echo "Port $PORT is beginning at $begintime and will expire at $endtime"
}

# Drop stop schedule by port
# $1 port
drop_stop_schedule() {
    PORT=$1

    if crontab -l 2>/dev/null | grep "stop $PORT" >/dev/null; then
        crontab -l > cron.stop.tmp
        sed -i '/stop '$PORT'/d' cron.stop.tmp
        crontab cron.stop.tmp
        rm -f cron.stop.tmp

        echo "Stop schedule of Port $PORT is dropped"
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
    # only options left in paras, otherwise getopts cannot recognize
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
        echo "updating and installing ..."
        sudo apt-get update >/dev/null 2>&1
        sudo apt-get install -y shadowsocks-libev=3.3.5+ds-10build3 >/dev/null
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
    bash `dirname "$0"`/write_conf.sh $PORT "$PASSCODE"
    # prompt when start
    sudo mv `[ $RESTART -eq 0 ] && echo '-i'` $PORT.tmp /etc/shadowsocks-libev/$PORT.json
    if [ $? -ne 0 ]; then
        rm -f $PORT.tmp
        echo "The start execution interrupted"
        exit 1
    fi
    # start service
    sudo systemctl enable shadowsocks-libev-server@$PORT.service
    sudo systemctl restart shadowsocks-libev-server@$PORT.service
    # show result(only 1st and 3rd line)
    sudo systemctl status shadowsocks-libev-server@$PORT.service | awk 'NR==1 || NR==3 {print}'
    echo "Please login with port $PORT and passcode $PASSCODE and AEAD chacha20-ietf-poly1305"

    # skip limit setting when restart
    if [ $RESTART -eq 1 ]; then
        exit 0
    fi
    # set data limit
    if [ -n "$DATA_LIMIT" ]; then
        create_data_limt $PORT "$DATA_LIMIT"
    else
        drop_data_limit $PORT
    fi
    # set stop schedule
    if [ -n "$TIME_LIMIT" ]; then
        create_stop_schedule $PORT "$TIME_LIMIT"
    else
        drop_stop_schedule $PORT
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
    if ! sudo systemctl disable shadowsocks-libev-server@$PORT.service --now >/dev/null 2>&1; then
        exit 1
    fi
    # remove conf file
    sudo rm /etc/shadowsocks-libev/$PORT.json 2>/dev/null
    # show result
    sudo systemctl status shadowsocks-libev-server@$PORT.service | awk 'NR==1 || NR==3 {print}'
    echo "Port $PORT was disabled"
    # drop data limit and stop schedule if exists
    drop_data_limit $PORT
    drop_stop_schedule $PORT
}

# update the latest usage and disable port if usage reached the limit.
# $1 ports
update_usage() {
    PORT=$1
    # calculate the latest data usage
    # tail column, usage/total(MB)/total, for example 0/10240M/10G
    usagestr=`crontab -l | grep "updateusage $PORT" | awk '{print $NF}'`
    # get total(MB)
    total=$(echo "$usagestr" | grep -oE '\/.*\/' | grep -oE '[0-9]+')
    # bytes
    sudo iptables -vnx -L SSIN  --line-numbers | grep "$PORT" > in_usage.tmp
    sudo iptables -vnx -L SSOUT --line-numbers | grep "$PORT" > out_usage.tmp
    tcp_in=$(grep "tcp" in_usage.tmp | awk '{print $3}')
    udp_in=$(grep "udp" in_usage.tmp | awk '{print $3}')
    tcp_out=$(grep "tcp" out_usage.tmp | awk '{print $3}')
    udp_out=$(grep "udp" out_usage.tmp | awk '{print $3}')
    sudo rm in_usage.tmp out_usage.tmp

    pdir=`dirname "$0"`
    # current io
    cur_io=$(expr $tcp_in + $udp_in + $tcp_out + $udp_out)
    # 0 timestamp | 1 tcpin| 2 udpin| 3 tcpout| 4 udpout| 5 inout| 6 diff| 7 usage
    prevline=$(tail -n 1 $pdir/log/$PORT.log)
    IFS=' '
    read -ra arr <<< "$preline"
    prev_tcp_in=${arr[1]}
    prev_udp_in=${arr[2]}
    prev_tcp_out=${arr[3]}
    prev_udp_out=${arr[4]}
    prev_io=${arr[5]}
    prev_usage=${arr[7]}
    # calculate diff
    if [ "$tcp_in" -ge "$prev_tcp_in" && "$udp_in" -ge "$prev_udp_in" && "$tcp_out" -ge "$prev_tcp_out" && "$udp_out" -ge "$prev_udp_out" ]; then
        # increase by degrees
        diff=$(expr $cur_io - $prev_io)
    else
        # rules has been recounted
        diff=$cur_io
    fi
    usage=$(expr $prev_usage + $diff)
    # write log
    echo "$(date '+%Y%m%dT%H:%M:%S') $tcp_in $udp_in $tcp_out $udp_out $cur_io $diff $usage">> $pdir/log/$PORT.log

    if [ "$usage" -lt "$((1024 * 1024 * total))" ]; then
        # create next update schedule
        crontab -l > cron.limit.tmp
        # delete before insert
        sed -i '/updateusage '$PORT'/d' cron.limit.tmp
        # update usage. usage/total(MB)/total
        memo=`sed -E 's/^[0-9]+/'$((usage / 1024 / 1024))'/' $usagestr`
        echo $(date -d "$(date) 1 hour" '+%M %H %d %m') "*" "bash $pdir/quickprep.sh updateusage $PORT $memo">> cron.limit.tmp
        crontab cron.limit.tmp
        rm -f cron.limit.tmp
    else
        # disable port when usage reached the limit
        disable_port $PORT
    fi
}

# show stauts
# $1~# port. Optional, show all when not given
show_status() {
    if [ -n "$1" ]; then
        ports="$@"
    else
        # get port according with json file name
        ports=`ls /etc/shadowsocks-libev/ 2>/dev/null | grep "^[0-9]" | rev | cut -d "." -f2- | rev`
        if [ `expr length "${ports[@]}"` -eq 0 ]; then
            echo "No service is in use"
            exit 0
        fi
    fi
    # usage
    sudo iptables -vn -L SSIN  --line-numbers 2>/dev/null > in_rules.tmp
    sudo iptables -vn -L SSOUT --line-numbers 2>/dev/null > out_rules.tmp

    for port in $ports
    do
        # show result
        sudo systemctl status shadowsocks-libev-server@$port.service 2>/dev/null | awk 'NR==1 || NR==3 {print}'
        # show usage
        if grep "$port" in_rules.tmp >/dev/null; then
            grep -E "num|$port" in_rules.tmp
        fi
        if grep "$port" out_rules.tmp >/dev/null; then
            grep -E "num|$port" out_rules.tmp
        fi
        # show data limit and stop schedule if exists
        crontab -l 2>/dev/null | grep "updateusage $port"
        crontab -l 2>/dev/null | grep "stop $port"
    done

    sudo rm in_rules.tmp out_rules.tmp
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
    updateusage)
        # for inner use
        update_usage $@
        ;;
    *)
        echo "Plese input start|restart|stop|status"
        ;;
esac
