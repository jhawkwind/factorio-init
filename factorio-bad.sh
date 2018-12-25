#!/bin/bash

### BEGIN INIT INFO
# Provides: Factorio
# Required-Start: $local_fs $network $remote_fs
# Required-Stop: $local_fs $network $remote_fs
# Default-Start:  2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: start and stop Factorio server
# Description: A init script for Factorio, try the help command
### END INIT INFO

debug(){
  if [ ${DEBUG} -gt 0 ]; then
    echo "DEBUG: $@" >&2
  fi
}

# Make sure the script is CD'ed to a PWD that is valid and not symlinked. (ie. where the script actually is at)
SOURCE="${BASH_SOURCE[0]}"
while [ -h "${SOURCE}" ]; do # resolve ${SOURCE} until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "${SOURCE}" )" && pwd )"
  SOURCE="$(readlink "${SOURCE}")"
  [[ ${SOURCE} != /* ]] && SOURCE="${DIR}/${SOURCE}" # if ${SOURCE} was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
cd "${SCRIPT_DIR}"

SCRIPT_ARGS=$@;

# Load config file
if [ -L $0 ]; then
  source `readlink -e $0 | sed "s:[^/]*$:config:"`
else
  source `echo $0 | sed "s:[^/]*$:config:"`
fi

if [ -z "${SERVICE_NAME}" ]; then
  echo "Couldn't load config file, please edit config.example and rename it to config"
  exit 1
fi

# Check/load defaults for backwards compatible config options
if [ -z "${PACKAGE_DIR_NAME}" ]; then
  PACKAGE_DIR_NAME=factorio
fi
if [ -z "${USERGROUP}" ]; then
  USERGROUP=${USERNAME}
fi
if [ -z "${HEADLESS}" ]; then
  # This is a server init script, assume headless default
  HEADLESS=1
fi
if [ -z "${LATEST_HEADLESS_URL}" ]; then
  if [ ${UPDATE_EXPERIMENTAL} -gt 0 ]; then
    LATEST_HEADLESS_URL="https://www.factorio.com/get-download/latest/headless/linux64"
  else
    LATEST_HEADLESS_URL="https://www.factorio.com/get-download/stable/headless/linux64"
  fi
fi
if [ -z "${NONCMDPATTERN}" ]; then
  NONCMDPATTERN='(^\s*(\s*[0-9]+\.[0-9]+|\)|\())|(Players:$)'
fi
if [ -z ${BINARY} ]; then
  # Factorio headless only comes in x64 flavour - if you run anything else, override it in the config
  BINARY="${FACTORIO_PATH}/bin/x64/factorio"
  BINARYB="${FACTORIO_PATH}/bin/x64/factorio"
fi
if [ -z ${ALT_GLIBC} ]; then
  ALT_GLIBC=0
fi
if [ -z ${WAIT_PINGPONG} ]; then
  WAIT_PINGPONG=0
fi

if [ ${ALT_GLIBC} -gt 0 ]; then
  # If ALT_GLIBC is non 0 then activate alternative glibc root here
  BINARY="${ALT_GLIBC_DIR}/lib/ld-${ALT_GLIBC_VER}.so --library-path ${ALT_GLIBC_DIR}/lib ${FACTORIO_PATH}/bin/x64/factorio"
  BINARYB="${FACTORIO_PATH}/bin/x64/factorio"
  EXE_ARGS_GLIBC="--executable-path ${BINARYB}"
fi
case "$1" in
  install|help|listcommands|version|init-server|"")
    ;;
  *)
    if ! [ -e ${BINARYB} ]; then
      echo "Could not find factorio binary! ${BINARYB}"
      echo "(if you store your binary some place else, override BINARY='/your/path' in the config)"
      exit 1
    fi
  
    if [ -z ${FCONF} ]; then
      FCONF="${FACTORIO_PATH}/config/config.ini"
    fi
  
    if ! [ -e "${SERVER_SETTINGS}" ]; then
      echo "Could not find factorio server settings file: ${SERVER_SETTINGS}"
      echo "Update your config and point SERVER_SETTINGS to a modified version of data/server-settings.example.json"
      exit 1
    fi
  
    if ! [ -e ${FCONF} ]; then
      echo "Could not find factorio config file: ${FCONF}"
      echo "If this is the first time you run this script you need to generate the config.ini by starting the server manually."
      echo "(also make sure you have a save to run or the server will not start)"
      echo
      echo "Create save: sudo -u ${USERNAME} ${BINARY} --create ${FACTORIO_PATH}/saves/my_savegame ${EXE_ARGS_GLIBC}"
      echo "Start server: sudo -u ${USERNAME} ${BINARY} --start-server-load-latest ${EXE_ARGS_GLIBC}"
      echo
      echo "(If you rather store the config.ini in another location, set FCONF='/your/path' in this scripts config file)"
      exit 1
    fi
    if [ -z "${WRITE_DIR}" ]; then
      # figure out the write-data path (where factorio looks for saves and mods)
      # Note - this is a hefty little operation, possible cause of head ache down the road
      # as it relies on the factorio write dir to live ../../ up from the binary if __PATH__executable__
      # is used in the config file.. for now, that's the default so cross your fingers it will not change ;)
      debug "Determining WRITE_DIR based on ${FCONF}, IF you edited write-data from the default, this probably fails"
      WRITE_DIR=$(dirname "$(echo `grep "^write-data=" "$FCONF"` |cut -d'=' -f2 |sed -e 's#__PATH__executable__#'$(dirname "$BINARYB")/..'#g')")
    fi
    debug "write path: $WRITE_DIR"
  
    PIDFILE="${WRITE_DIR}/server.pid"
  
    if [ -z "${FIFO}" ];then
      FIFO="${WRITE_DIR}/server.fifo"
    fi
  
    if [ -z "${CMDOUT}" ];then
      CMDOUT="${WRITE_DIR}/server.out"
    fi
  
    if [ -z "${SAVELOG}" ]; then
      SAVELOG=0
    fi
  
    # Finally, set up the invocation
    INVOCATION="${BINARY} --config ${FCONF} --port ${PORT} --start-server-load-latest --server-settings ${SERVER_SETTINGS} ${EXTRA_BINARGS}"
    ;;
esac
  
usage(){
  echo "Usage: $0 COMMAND"
  echo
  echo "Available commands:"
  echo -e "   start \t\t\t\t Starts the server"
  echo -e "   stop \t\t\t\t Stops the server"
  echo -e "   restart \t\t\t\t Restarts the server"
  echo -e "   status \t\t\t\t Displays server status"
  echo -e "   players-online \t\t\t Shows online players"
  echo -e "   players \t\t\t\t Shows all players"
  echo -e "   cmd [command/message] \t\t Open interactive commandline or send a single command to the server"
  echo -e "   chatlog [--tail|-t] \t\t\t Print the current chatlog, optionally tail the log to follow in real time"
  echo -e "   new-game name [map-gen-settings] [map-settings] \t Stops the server and creates a new game with the specified name using the specified map gen settings and map settings json files"
  echo -e "   save-game name \t\t\t Stops the server and saves game to specified save"
  echo -e "   load-save name \t\t\t Stops the server and loads the specified save"
  echo -e "   install [tarball] \t\t\t Installs the server with optional specified tarball (omit to download and use the latest headless server from Wube)"
  echo -e "   update [--dry-run] \t\t\t Updates the server"
  echo -e "   invocation \t\t\t\t Outputs the invocation for debugging purpose"
  echo -e "   listcommands \t\t\t List all init-commands"
  echo -e "   listsaves \t\t\t\t List all saves"
  echo -e "   version \t\t\t\t Prints the binary version"
  echo -e "   help \t\t\t\t Shows this help message"
}

ME=`whoami`

check_user() {
	# This function makes sure that the whole script is running the proper context.
	# Only the "install" does not call this function, as we need to run as root.
	if [ $ME != $USERNAME ] && [ "$(id -u)" == "0" ]; then # Not factorio user, and root, switch user.

  		exec su "$USERNAME" -s /bin/bash -c "${SCRIPT_DIR}/factorio $@"
  		
  		# nothing will be executed beyond that line,
  		# because exec replaces running process with the new one
  		exit $?; # Paranoia
	elif [ $ME == $USERNAME ] && [ "${SELINUX}" -eq 1 ]; then
		factorio_init_context_string="^system_u:system_r:factorio_init_t:.*"
		if ! [[ "$(id -Z)" =~ ${factorio_init_context_string} ]]; then
			exec runcon -t factorio_init_t -r system_r -u system_u "${SCRIPT_DIR}/factorio" "$@"
			exit $?;
		fi
	fi

	umask 0022; # Set this in case things are too restrictive for Factorio.
}

as_user() {
  if [ ${SELINUX} -eq 1 ]; then # For the sake of clarity with SELINUX diagnostics.
	logger "$(whoami) with context $(id -Z) executing: "
	logger "${1}"
  fi
  
  factorio_context_string="^system_u:system_r:factorio_t:.*"
  if [ $ME == $USERNAME ]; then # Are we the factorio user?
  		
  	  # Is SELINUX enabled and we are not already in the proper context?
	  if [ ${SELINUX} -eq 1 ] && ( ! [[ "$(id -Z)" =~ ${factorio_context_string} ]]); then
    	runcon -t factorio_t -r system_r -u system_u -- ${1}
      else
    	/bin/bash -c "$1"
      fi
  elif [ "$(id -u)" == "0" ]; then # Are we root?
      exec su "$USERNAME" -s /bin/bash -c "${SCRIPT_DIR}/factorio ${SCRIPT_ARGS}"
  else
    # To prevent odd permission behaviour, either
    # run this script as the configured user or as root
    # (please do not run as root btw!)
    echo "Run this script as the $USERNAME user!"
    exit 1
  fi
}

is_running() {
  if [ -e ${PIDFILE} ]; then
    if kill -0 $(cat ${PIDFILE}) 2> /dev/null; then
      debug "${SERVICE_NAME} is running with pid $(cat ${PIDFILE})"
      return 0
    else
      debug "Found ${PIDFILE}, but the server is not running. It's possible that your server has crashed"
      debug "Check the log for details"
      rm ${PIDFILE} 2> /dev/null
      return 2
    fi
  fi
  return 1
}

wait_pingpong() {
  until ping -c1 pingpong1.factorio.com &>/dev/null; do :; done
  until ping -c1 pingpong2.factorio.com &>/dev/null; do :; done
}

start_service() {
  if [ -e ${PIDFILE} ]; then
    ps -q $(cat ${PIDFILE}) > /dev/null 2>&1
    if [ "$?" -eq "0" ]; then
      echo "${SERVICE_NAME} is already running!"
      return 1
    fi
    debug "Found rogue pid file, server might have crashed"
    rm ${PIDFILE} 2> /dev/null
  fi

  if ! check_permissions; then
    echo "Error! Incorrect permissions, unable to write to ${WRITE_DIR}"
    return 1
  fi

  if [ "${SAVELOG}" ==  "0" ]; then
    debug "Erasing log ${CMDOUT}"
    echo "" > ${CMDOUT}
  fi

  if [ ${WAIT_PINGPONG} -gt 0 ]; then
    wait_pingpong
  fi

  as_user "tail -f ${FIFO} |${INVOCATION} ${EXE_ARGS_GLIBC}>> ${CMDOUT} 2>&1 & echo \$! > ${PIDFILE}"

  ps -q $(cat ${PIDFILE}) > /dev/null 2>&1
  if [ "$?" -ne "0" ]; then
    echo "Unable to start ${SERVICE_NAME}"
    return 1
  else
    echo "Started ${SERVICE_NAME}, please see log for details"
  fi
}

stop_service() {
  if [ -e ${PIDFILE} ]; then
    echo -n "Stopping ${SERVICE_NAME}: "
    if kill -TERM $(cat ${PIDFILE} 2> /dev/null) 2> /dev/null; then
      sec=1
      while [ "$sec" -le 15 ]; do
        if [ -e ${PIDFILE} ]; then
          if kill -0 $(cat ${PIDFILE} 2> /dev/null) 2> /dev/null; then
            echo -n ". "
            sleep 1
          else
            break
          fi
        else
          break
        fi
        sec=$(($sec+1))
      done
    fi

    if kill -0 $(cat ${PIDFILE} 2> /dev/null) 2> /dev/null; then
      echo "Unable to shut down nicely, killing the process!"
      kill -KILL $(cat ${PIDFILE} 2> /dev/null) 2> /dev/null
    else
      echo "complete!"
    fi

    # Start the reader (in case tail stopped already)
    cat ${FIFO} &
    # Open pipe for writing.
    exec 3> ${FIFO}
    # Write a newline to the pipe, this triggers a SIGPIPE and causes tail to exit
    echo "" >&3
    # Close pipe.
    exec 3>&-

    rm ${PIDFILE} 2> /dev/null
    return 0 # we've either shut down gracefully or killed the process
  else
    echo "${SERVICE_NAME} is not running (${PIDFILE} does not exist)"
    return 1
  fi
}

send_cmd(){
  NEED_OUTPUT=0
  if [ "xx$1" == "xx-o" ]; then
    NEED_OUTPUT=1
    shift
  fi
  if is_running; then
    if [ -p ${FIFO} ]; then
      # Generate two unique log markers
      TIMESTAMP=$(date +"%s")
      START="FACTORIO_INIT_CMD_${TIMESTAMP}_START"
      END="FACTORIO_INIT_CMD_${TIMESTAMP}_END"

      # Whisper that unknown player to place start marker in log
      echo "/w $START" > ${FIFO}
      # Run the actual command
      echo $@ > ${FIFO}
      # Whisper that unknown player again to place end marker in log after the command terminated
      echo "/w $END" > ${FIFO}

      if [ ${NEED_OUTPUT} -eq 1 ]; then
        # search for the start marker in the log file, then follow and print the log output in real time until the end marker is found
        sleep 1
        awk "/Player $START doesn't exist./{flag=1;next}/Player $END doesn't exist./{exit}flag" < ${CMDOUT}
      fi
    else
      echo "${FIFO} is not a pipe!"
      return 1
    fi
  else
    echo "Unable to send cmd to a stopped server!"
    return 1
  fi
}

cmd_players(){
  players=$(send_cmd -o "/p")
  if [ -z "${players}" ]; then
    echo "No players found!"
    return 1
  fi

  if [ "$1" == "online" ]; then
    echo "${players}" |egrep '.+ \(online\)$' |sed -e 's/ (online)//g'
  else
    echo "${players}"
  fi
}

check_permissions(){
	
  if [ $ME != $USERNAME ]; then
  	echo "You must run as ${USERNAME}."
  	exit 1
  fi
  	
  if [ ! -e "${BINARYB}" ]; then
    echo "Can't find ${BINARYB}. Please check your config!"
    exit 1
  fi

  if ! test -w ${WRITE_DIR} ; then
    echo "Check Permissions. Cannot write to ${WRITE_DIR}"
    exit 1
  fi

  if ! touch ${PIDFILE} ; then
    echo "Check Permissions. Cannot touch pidfile ${PIDFILE}"
    exit 1
  fi

  if ! [ -p ${FIFO} ]; then
    if ! mkfifo ${FIFO}; then
      echo "Failed to create pipe for stdin, if applicable, remove ${FIFO} and try again"
      exit 1
    fi
  fi

  if ! touch ${CMDOUT} ; then
    echo "Check Permissions. Cannot touch cmd output file ${CMDOUT}"
    exit 1
  fi
}

test_deps(){
  return 0 # TODO: Implement ldd check on $BINARY
}

set_perms(){
  echo "Applying file ownership ..."
  result=$(chown -R ${USERNAME}:${USERGROUP} ${FACTORIO_PATH})
  if [[ ${result} -ne 0 ]]; then
    echo "Failed to apply ownership ${USERNAME}:${USERGROUP} for ${FACTORIO_PATH}"
    exit 1
  fi
 
  echo "Applying file permission ..."
  result=$(find ${FACTORIO_PATH} -type d -exec chmod 755 {} \;)
  if [[ ${result} -ne 0 ]]; then
    echo "Failed to apply permission for ${FACTORIO_PATH}"
    exit 1
  fi
 
  if [[ ${SELINUX} -eq 1 ]]; then
  	echo "Applying SELINUX security contexts ..."
  	result=$(restorecon -R -v ${FACTORIO_PATH})
  	if [[ ${result} -ne 0 ]]; then
  	  echo "Failed to apply SELINUX security contexts for ${FACTORIO_PATH}"
  	  exit 1
  	fi
  fi
}

install(){
  # Factorio comes packaged in a directory named "factorio"
  # Unless overriden in the config we will presume this is also the
  # name used in FACTORIO_PATH
  expected_path="$(dirname ${FACTORIO_PATH})/${PACKAGE_DIR_NAME}"
  if ! [ "${FACTORIO_PATH}" == "${expected_path}" ]; then
    echo "Aborting install! FACTORIO_PATH does not match expected path: ${expected_path}"
    echo "See config option PACKAGE_DIR_NAME for more details"
    exit 1
  fi

  # Prevent accidential overwrites
  if [ -e "${expected_path}" ]; then
    echo "Aborting install, ${FACTORIO_PATH} already exists"
    exit 1
  fi

  # See if we need to compile GLIBC
  if [ "${ALT_GLIBC}" -eq 1 ]; then
  	if ! [ -f "${ALT_GLIBC_DIR}/lib/ld-${ALT_GLIBC_VER}.so" ]; then
      #install_glibc();
      echo ""
  	fi
  fi

  tarball=$1
  if ! [ -z "$tarball" ]; then
    if ! [ -f "${tarball}" ]; then
      echo "Install package does not exist! ${tarball}"
      exit 1
    fi
  else
    downloadlatest=1
  fi

  target="$(dirname ${FACTORIO_PATH})"
  if ! test -w "${target}"; then
    echo "Failed to write, aborting install!"
    echo "Install needs to be run as a user with write permissions to ${target}"
    echo "Please create empty folder ${target}"
    exit 1
  fi

  if [ $downloadlatest ]; then
    LATEST_HEADLESS_URL_REDIRECT_FILENAME=$(curl ${LATEST_HEADLESS_URL} -s -L -I -o /dev/null -w '%{url_effective}')
    if [[ $LATEST_HEADLESS_URL_REDIRECT_FILENAME == *"tar.xz"* ]]; then 
      TAR_OPTIONS="-xJv"
    else
      TAR_OPTIONS="-xzv"
    fi
    if ! wget ${LATEST_HEADLESS_URL} -O - | tar ${TAR_OPTIONS} --directory "${target}"; then
      echo "Install failed!"
      exit 1
    fi
  else
    echo "Installing ${tarball} ..."
    if [[ $tarball == *"tar.xz"* ]]; then 
      TAR_OPTIONS="-xJvf"
    else
      TAR_OPTIONS="-xzvf"
    fi
    if ! tar ${TAR_OPTIONS} "${tarball}" --directory "${target}"; then
      echo "Install failed!"
      exit 1
    fi
  fi
  
  set_perms; # Set file permissions

  # Generate default config.ini by creating a save. And restart script to ensure that it is in the proper context.
  ${SCRIPT_DIR}/factorio init-server
  if [ $? -eq 0 ]; then
    echo "Installation complete, edit data/server-settings.json and start your server"
    exit 0
  else
    echo "Failed to create save, review the output above to recover"
    exit 1
  fi
}

init-server(){
  if [ ! -f "${SERVER_SETTINGS}" ]; then
    as_user "${BINARY} --create ${FACTORIO_PATH}/saves/server-save ${EXE_ARGS_GLIBC}";
    resutling_status=$?;
    exit $?;
  else
  	echo "You cannot re-initialize a server that is ALREADY initialized at ${SERVER_SETTINGS}!";
    exit 1;
  fi
}

get_bin_version(){
  echo "$(as_user '${BINARY} --version')" |egrep '^Version: [0-9\.]+' |egrep -o '[0-9\.]+[^\s]' |head -n 1
}

get_bin_arch(){
  echo "$(as_user '${BINARY} --version')" |egrep '^Binary version: ' |egrep -o '[0-9]{2}'
}

update(){
  if ! [ -e "${UPDATE_SCRIPT}" ]; then
    echo "Failed to find update script, blatantly refusing to continue!"
    echo "Try cloning into git@github.com:narc0tiq/factorio-updater.git and set the UPDATE_SCRIPT config before you try again."
    exit 1
  fi

  # Assume the user wants a dry run? (our only argument to this function)
  if ! [ -z "$1" ]; then
    echo "Running updater in --dry-run mode, no patches will be applied"
    dryrun=1
  else
    dryrun=0
  fi

  if [ ${HEADLESS} -gt 0 ]; then
    package="core-linux_headless`get_bin_arch`"
  else
    package="core-linux`get_bin_arch`"
  fi

  version=`get_bin_version`
  if [ -z "${UPDATE_TMPDIR}" ]; then
    UPDATE_TMPDIR=/tmp
  fi

  # Create tmpdir and ensure automatic cleanup
  tmpdir=`as_user "mktemp -d -p ${UPDATE_TMPDIR} factorio-update.XXXXXXXXXX"`
  if [ $? -ne 0 ]; then
    echo "Aborting update! Unable to create tmpdir: ${tmpdir}"
    exit 1
  fi
  trap "rm -rf ${tmpdir}" EXIT
    
  invocation="python ${UPDATE_SCRIPT} --for-version ${version} --package ${package} --output-path ${tmpdir}"
  if [ ${UPDATE_EXPERIMENTAL} -gt 0 ]; then
    invocation="${invocation} --experimental"
  fi

  if [ ${HEADLESS} -eq 0 ]; then
    #GoodGuy Wube Software allows you to download the headless for free - yay! but you still have to
    #buy the game if you want to download the sound/gfx client
    invocation="${invocation} --user ${UPDATE_USERNAME} --token ${UPDATE_TOKEN}"
  fi

  echo "Checking for updates..."
  result=`as_user "${invocation} --dry-run"`
  exitcode=$?
  if [ ${exitcode} -eq 1 -o ${exitcode} -gt 2 ]; then
    debug "Invocation: ${invocation}"
    debug "${result}"
    echo "Update check failed!"
    exit 1
  else
    newversion=`echo ${result} |egrep '^Dry run: ' |egrep -o '[0-9\.]+' |tail -n 1`
  fi

  if [ -z "${newversion}" ]; then
    echo "No new updates for ${package} ${version}"
    exit 0
  else
    echo "New version ${package} ${newversion}"
  fi

  # Go or no Go?
  if [ ${dryrun} -gt 0 ]; then
    echo "Dry run, not taking further actions!"
    # allow scripts to read return code 0 for no updates and 2 if there are updates to apply
    if ! [ -z "${newversion}" ]; then
      exit 2
    fi
    exit 0
  fi

  # Time to download the updates
  if ! as_user "${invocation}"; then
    echo "Aborting update!"
    exit 1
  fi

  # Stop the server if it is running.
  is_running
  was_running=$?
  if [ ${was_running} -eq 0 ]; then
    send_cmd "Updating to new Factorio version, be right back"
    stop_service
  fi

  for patch in $(find ${tmpdir} -type f -name "*.zip" | sort -V); do
    echo "Applying ${patch} ..."
    result=`as_user "$BINARY --apply-update ${patch} ${EXE_ARGS_GLIBC}"`
    exitcode=$?
    if [ $exitcode -gt 0 ]; then
      echo "${result}"
      echo
      echo "Error! Failed to apply update"
      echo "You can try to apply it manually with:"
      echo "su ${USERNAME} -c \"${BINARY} --apply-update ${patch} ${EXE_ARGS_GLIBC}\""
      exit 1
    fi
  done
  
  # Restarts the server if it was running
  if [ ${was_running} -eq 0 ]; then
    start_service
  fi

  echo "Successfully updated factorio"
}

case "$1" in
  start)
    check_user $@; # Check to make sure we are running the correct context.
    # Starts the server
    if is_running; then
      echo "Server already running."
      exit 0
    else
       if ! start_service; then
         echo "Could not start $SERVICE_NAME"
         exit 1
       fi
    fi
    ;;

  stop)
    check_user $@; # Check to make sure we are running the correct context.
    # Stops the server
    if is_running; then
      send_cmd "Server is being shut down on request"
      if ! stop_service; then
        echo "Could not stop $SERVICE_NAME"
        exit 1
      fi
    else
      echo "No running server."
      exit 0
    fi
    ;;

  restart)
    check_user $@; # Check to make sure we are running the correct context.
    # Restarts the server
    if is_running; then
      send_cmd "Server is being restarted on request, be right back!"
      if stop_service; then
        if ! start_service; then
          echo "Could not start $SERVICE_NAME after restart!"
          exit 1
        fi
      else
        echo "Failed to stop $SERVICE_NAME, aborting restart!"
        exit 1
      fi
    else
      echo "No running server to restart, starting it..."
      if ! start_service; then
        echo "Could not start $SERVICE_NAME"
        exit 1
      fi
    fi
    ;;
  init-server)
  	check_user $@; # Check to make sure we are running the correct context.
    init-server;
    exit 2;
    ;;
  status)
  	check_user $@; # Check to make sure we are running the correct context.
    # Shows server status
    if is_running; then
      echo "$SERVICE_NAME is running."
    else
      echo "$SERVICE_NAME is not running."
      exit 1
    fi
    ;;
  cmd)
    if [ -z "$2" ]; then
      trap 'clear' SIGTERM EXIT

      clear
      echo "Type any command or send chat messages"
      echo "This interactive commandline adds additional commands:"
      echo ""
      echo -e "\texit\t\texit the commandline"
      echo -e "\tclear\t\tclear the commandline screen"
      echo ""

      while true; do
        read -e -p "server@${SERVICE_NAME}> " cmd
        [ "${cmd}" == "exit" ] && exit 0
        [ "${cmd}" == "clear" ] && clear && continue
        echo ${cmd} > ${FIFO}
        sleep 1
      done
    else
      send_cmd "${@:2}"
    fi
    ;;
  chatlog)
    check_user $@; # Check to make sure we are running the correct context.
    case $2 in
      --tail|-t)
        tail -F -n +0 ${CMDOUT} |egrep -v "${NONCMDPATTERN}"
        ;;
      *)
        cat ${CMDOUT} |egrep -v "${NONCMDPATTERN}"
        ;;
    esac
    ;;
  players)
    check_user $@; # Check to make sure we are running the correct context.
    cmd_players
    ;;
  players-online|online)
    check_user $@; # Check to make sure we are running the correct context.
    cmd_players online
    ;;
  new-game)
    check_user $@; # Check to make sure we are running the correct context.
    if [ -z $2 ]; then
      echo "You must specify a save name for your new game"
      exit 1
    fi
    savename="${WRITE_DIR}/saves/$2"
    createsavecmd="$BINARY --create \"${savename}\""

    # Check if user wants to use custom map gen settings
    if [ $3 ]; then
      if [ -e "${WRITE_DIR}/$3" ]; then
        createsavecmd="$createsavecmd --map-gen-settings=${WRITE_DIR}/$3 ${EXE_ARGS_GLIBC}"
      else
        echo "Specified map gen settings json does not exist"
        exit 1
      fi
    fi

    # Check if user wants to use custom map settings
    if [ $4 ]; then
      if [ -e "${WRITE_DIR}/$4" ]; then
        createsavecmd="$createsavecmd --map-settings=${WRITE_DIR}/$4 ${EXE_ARGS_GLIBC}"
      else
        echo "Specified map settings json does not exist"
        exit 1
      fi
    fi

    # Stop Service
    if is_running; then
      send_cmd "Generating new save, please stand by"
      if ! stop_service; then
        echo "Failed to stop server, unable to create new save"
        exit 1
      fi
    fi

    if ! as_user "$createsavecmd"; then
      echo "Failed to create new game"
      exit 1
    else
      echo "New game created: ${savename}.zip"
    fi
    ;;

  save-game)
    check_user $@; # Check to make sure we are running the correct context.
    savename="${WRITE_DIR}/saves/$2.zip"

    # Stop Service
    if is_running; then
      send_cmd "Stopping server to save game"
      if ! stop_service; then
        echo "Failed to stop server, unable to save as \"$2\""
        exit 1
      fi
    fi

    lastsave=$(find "${WRITE_DIR}/saves" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -f2- -d" ")
    if ! as_user "cp \"${lastsave}\" \"${savename}\""; then
      echo "Error! Failed to save game"
      exit 1
    fi
    ;;

  load-save)
    check_user $@; # Check to make sure we are running the correct context.
    # Ensure we get a new save file name
    newsave=${WRITE_DIR}/saves/$2.zip
    if [ ! -f "${newsave}" ]; then
      echo "Save \"${newsave}\" does not exist, aborting action!"
      exit 1
    fi

    # Since stopping the server causes a save we have to stop the server to do this
    if is_running; then
      send_cmd "Stopping server to load a saved game"
      if ! stop_service; then
        echo "Aborting, unable to stop $SERVICE_NAME"
        exit 1
      fi
    fi

    # Touch the new save file
    as_user "touch \"${newsave}\""
    ;;
  install)
    install "$2"
    ;;
  update)
    update "$2"
    ;;
  inv|invocation)
    echo ${INVOCATION}
    ;;
  help|--help|-h)
    usage
    ;;
  listcommands)
    check_user $@; # Check to make sure we are running the correct context.
    echo `$0 help 2> /dev/null |egrep '^   ' |awk '{ print $1 }'`
    ;;
  listsaves)
    check_user $@; # Check to make sure we are running the correct context.
    find ${WRITE_DIR} -type f -name "*.zip" -exec basename {} \; |sed -e 's/.zip//'
    ;;
  version)
    check_user $@; # Check to make sure we are running the correct context.
    echo `get_bin_version`
    ;;
  source)
    # do not call `exit` and just return successfully, so that other scripts (possibly with set -e) may source this script to import all out variables and functions
    return 0
    ;;
  *)
    echo "No such command!"
    echo
    usage
    exit 1
    ;;
esac

exit 0
