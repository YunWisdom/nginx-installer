#! /bin/sh
### BEGIN INIT INFO
# Provides:          nginx
# Required-Start:    $remote_fs $syslog
# Required-Stop:     $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: nginx init.d bash script for debian/ubuntu
# Description:       nginx init.d bash script for debian/ubuntu
### END INIT INFO

#------------------------------------------------------------------------------
#                               Functions
#------------------------------------------------------------------------------
. /lib/lsb/init-functions

#------------------------------------------------------------------------------
#                               Consts
#------------------------------------------------------------------------------
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
DAEMON=/usr/local/nginx/sbin/nginx

PS="nginx"
PIDNAME="nginx"                         #lets you do $PS-slave
PIDFILE=$PIDNAME.pid                    #pid file
PIDSPATH=/var/run

DESCRIPTION="Nginx Server..."

RUNAS=root                              #user to run as

SCRIPT_OK=0                             #ala error codes
SCRIPT_ERROR=1                          #ala error codes
TRUE=1                                  #boolean
FALSE=0                                 #boolean

lockfile=/var/lock/subsys/nginx
NGINX_CONF_FILE="/usr/local/nginx/conf/nginx.conf"

#------------------------------------------------------------------------------
#                               Simple Tests
#------------------------------------------------------------------------------

#test if nginx is a file and executable
test -x $DAEMON || exit 0

# Include nginx defaults if available
if [ -f /etc/default/nginx ] ; then
    . /etc/default/nginx
fi

#set exit condition
#set -e

#------------------------------------------------------------------------------
#                               Functions
#------------------------------------------------------------------------------

setFilePerms(){
    if [ -f $PIDSPATH/$PIDFILE ]; then
        chmod 400 $PIDSPATH/$PIDFILE
    fi
}

configtest() {
    $DAEMON -t -c $NGINX_CONF_FILE
}

getPSCount() {
    return `pgrep -f $PS | wc -l`
}

isRunning() {
    if [ $1 ]; then
        pidof_daemon $1
        PID=$?

        if [ $PID -gt 0 ]; then
            return 1
        else
            return 0
        fi
    else
        pidof_daemon
        PID=$?

        if [ $PID -gt 0 ]; then
            return 1
        else
            return 0
        fi
    fi
}

#courtesy of php-fpm
wait_for_pid () {
    try=0

    while test $try -lt 35 ; do

        case "$1" in
            'created')
                if [ -f "$2" ] ; then
                    try=''
                    break
                fi
            ;;

            'removed')
                if [ ! -f "$2" ] ; then
                    try=''
                    break
                fi
            ;;
        esac

        #echo -n .
        try=`expr $try + 1`
        sleep 1
    done
}

status(){
    isRunning
    isAlive=$?

    if [ "${isAlive}" -eq $TRUE ]; then
        echo "$PIDNAME found running with processes:  `pidof $PS`"
    else
        echo "$PIDNAME is NOT running."
    fi
}

removePIDFile(){
    if [ $1 ]; then
        if [ -f $1 ]; then
            rm -f $1
        fi
    else
        #Do default removal
        if [ -f $PIDSPATH/$PIDFILE ]; then
            rm -f $PIDSPATH/$PIDFILE
        fi
    fi
}

start() {
    log_daemon_msg "Starting $DESCRIPTION"

    isRunning
    isAlive=$?

    if [ "${isAlive}" -eq $TRUE ]; then
        log_end_msg $SCRIPT_ERROR
    else
        start-stop-daemon --start --quiet --chuid $RUNAS --pidfile $PIDSPATH/$PIDFILE --exec $DAEMON -- -c $NGINX_CONF_FILE
        setFilePerms
        log_end_msg $SCRIPT_OK
    fi
}

stop() {
    log_daemon_msg "Stopping $DESCRIPTION"

    isRunning
    isAlive=$?

    if [ "${isAlive}" -eq $TRUE ]; then
        start-stop-daemon --stop --quiet --pidfile $PIDSPATH/$PIDFILE

        wait_for_pid 'removed' $PIDSPATH/$PIDFILE

        if [ -n "$try" ] ; then
            log_end_msg $SCRIPT_ERROR
        else
            removePIDFile
            log_end_msg $SCRIPT_OK
        fi
    else
        log_end_msg $SCRIPT_ERROR
    fi
}

reload() {
    configtest || return $?

    log_daemon_msg "Reloading (via HUP) $DESCRIPTION"

    isRunning

    if [ $? -eq $TRUE ]; then
        `killall -HUP $PS` #to be safe
        log_end_msg $SCRIPT_OK
    else
        log_end_msg $SCRIPT_ERROR
    fi
}

quietupgrade() {
    log_daemon_msg "Peforming Quiet Upgrade $DESCRIPTION"

    isRunning
    isAlive=$?

    if [ "${isAlive}" -eq $TRUE ]; then
        kill -USR2 `cat $PIDSPATH/$PIDFILE`
        kill -WINCH `cat $PIDSPATH/$PIDFILE.oldbin`

        isRunning
        isAlive=$?

        if [ "${isAlive}" -eq $TRUE ]; then
            kill -QUIT `cat $PIDSPATH/$PIDFILE.oldbin`
            wait_for_pid 'removed' $PIDSPATH/$PIDFILE.oldbin
            removePIDFile $PIDSPATH/$PIDFILE.oldbin

            log_end_msg $SCRIPT_OK
        else
            log_end_msg $SCRIPT_ERROR

            log_daemon_msg "ERROR! Reverting back to original $DESCRIPTION"

            kill -HUP `cat $PIDSPATH/$PIDFILE`
            kill -TERM `cat $PIDSPATH/$PIDFILE.oldbin`
            kill -QUIT `cat $PIDSPATH/$PIDFILE.oldbin`

            wait_for_pid 'removed' $PIDSPATH/$PIDFILE.oldbin
            removePIDFile $PIDSPATH/$PIDFILE.oldbin

            log_end_msg $SCRIPT_ok
        fi
    else
        log_end_msg $SCRIPT_ERROR
    fi
}

terminate() {
    log_daemon_msg "Force terminating (via KILL) $DESCRIPTION"

    PIDS=`pidof $PS` || true

    [ -e $PIDSPATH/$PIDFILE ] && PIDS2=`cat $PIDSPATH/$PIDFILE`

    for i in $PIDS; do
        if [ "$i" = "$PIDS2" ]; then
                kill $i
                wait_for_pid 'removed' $PIDSPATH/$PIDFILE
            removePIDFile
        fi
    done

    log_end_msg $SCRIPT_OK
}

destroy() {
    log_daemon_msg "Force terminating and may include self (via KILLALL) $DESCRIPTION"
    killall $PS -q >> /dev/null 2>&1
    log_end_msg $SCRIPT_OK
}

pidof_daemon() {
    PIDS=`pidof $PS` || true

    [ -e $PIDSPATH/$PIDFILE ] && PIDS2=`cat $PIDSPATH/$PIDFILE`

    for i in $PIDS; do
        if [ "$i" = "$PIDS2" ]; then
            return 1
        fi
    done

    return 0
}

case "$1" in
    start)
        start
    ;;
    stop)
        stop
    ;;
    restart|force-reload)
        stop
        sleep 1
        start
    ;;
    reload)
        $1
    ;;
    status)
        status
    ;;
    configtest)
        $1
    ;;
    quietupgrade)
        $1
    ;;
    terminate)
        $1
    ;;
    destroy)
        $1
    ;;
    *)
        FULLPATH=/etc/init.d/$PS
        echo "Usage: $FULLPATH {start|stop|restart|force-reload|status|configtest|quietupgrade|terminate|destroy}"
        echo "       The 'destroy' command should only be used as a last resort."
        exit 1
    ;;
esac

exit 0