#!/bin/bash
#
# A bash script/template for adding multi-processing to "stuff".
#
# Designed to be used for syncing files though. Takes "strings of stuff" (eg.
# filenames) into a queue, flattens duplicates, then spawns a worker after a
# few seconds that calls the processing script with the "stuff" as params.
#
# dsimmons@squiz.co.uk
# 2011-02-24
#

# Command for worker to execute
#worker_cmd="$(dirname $0)/do-something.sh"
worker_cmd="echo"

# Whether the worker cmd can take more than one parameter at a time
worker_cmd_multiple=1

# Delay before spawning worker
worker_delay=5

# Filename of log for daemon
log=$(dirname $0)/$(basename $0 .sh).log

# Filename of listener pipe
pipe="/tmp/$(basename $0 .sh)"

# Set this to newline as it makes working with arrays easier
IFS=$'\n'

print() {
	echo "[$(date)][$$]:" $*
}

listener()
{
	# This variable is exported and read at startup so a worker process knows if it's a child or not
	export LISTENER=$$

	if ! mkfifo $pipe; then
		echo "ERROR: Failed to create pipe: $pipe, exiting (is a listener already running?)" >&2
		exit 1
	fi

	trap "rm -f $pipe" EXIT	

	chmod 0666 $pipe
	exec 3<> $pipe
	
	print "Daemon started. Listening at $pipe"
	
	declare -a queue

	while true; do
	
		# Read filenames from pipe. After x seconds of receiving nothing (delay), kick off the worker.
		if read -t $worker_delay line <&3; then
			print "Received: \"$line\". Adding to queue."
			queue=( "${queue[@]}" "$line" )
		else
			if [ ${#queue[@]} -gt 0 ]; then

				# uniq array
				params=$(echo "${queue[*]}" |sort |uniq)

				print "Spawning worker (work set: \"$params\")"
				$0 $params &

				unset queue
			fi
		fi
	done
}

worker()
{
	print "Worker started."

	if [ $worker_cmd_multiple -gt 0 ]; then
		print "Launching command \"$worker_cmd\" for \"$@\"";
		IFS=' '
		$worker_cmd "$@"
		IFS=$'\n'
		[ $? -gt 0 ] && echo "Command failed." >&2

	else
		for i in "$@"; do
			print "Launching command \"$worker_cmd\" for \"$i\"";
			IFS=' '
			$worker_cmd "$i"
			IFS=$'\n'
			[ $? -gt 0 ] && echo "Command failed." >&2
		done
	fi

	print "Worker finished."
}

add_to_queue()
{
	if [ ! -p "$pipe" ]; then
		echo "Sorry, can't add this to the queue because no background listener is running!" >&2
		exit 1
	fi

	if [ "$1" == "-n" ]; then	
		set -m
		shift
		(echo "$*" >> $pipe) &
		disown
		exit
	else
		echo "$*" >> $pipe
	fi
}

if [ ! -z $LISTENER ]; then
	worker $*
	exit
fi

case $1 in
	--d*|-d*)
		shift
		if [ "$1" == "-f" ]; then
			shift
			listener $*
		else
			set -m
			$0 --daemon -f $* 2>&1 1>>$log &
			disown
		fi
		;;
	--a*|-a*)
		shift
		add_to_queue $*
		;;
	*)
		echo "Usage: $0 --daemon [-f]      Starts the listener daemon that watches the queue for events and spawns workers. (-f means no detach)" >&2
		echo "       $0 --add [-n] <item>  Adds an item to the queue. (-n means don't confirm it's been read; exit immediately) " >&2
		exit 99
esac
