#!/bin/bash

############################################################################
# Bash script to control the NanoPi M4 SATA hat PWM1 fan via sysfs interface
############################################################################
# Officila sysfs doc:
# https://www.kernel.org/doc/Documentation/pwm.txt
###########################################################################

start () {
	echo '####################################################'
	echo '# STARTING PWM-FAN SCRIPT'
	echo '# Date and time: '$(date)
	echo '####################################################'
}

# accept message and status as argument
end () {
	cleanup
	echo '####################################################'
	echo '# END OF THE PWM-FAN SCRIPT'
	echo '# MESSAGE: '$1
	echo '####################################################'
	exit $2
}

# takes a name as argument
cache () {
	if [[ -z "$1" ]]; then
		echo '[pwm-fan] Cache file was not specified. Assuming generic.'
		local FILENAME='generic'
	else
		local FILENAME="$1"
	fi
	# cache to memory
	CACHE_ROOT='/tmp/pwm-fan/'
	if [[ ! -d "$CACHE_ROOT" ]]; then
		mkdir "$CACHE_ROOT"
	fi
	CACHE=$CACHE_ROOT$FILENAME'.cache'
	if [[ ! -f "$CACHE" ]]; then
		touch "$CACHE"
	else
		> "$CACHE"
	fi
}

cleanup () {
	echo '---- cleaning up ----'
	unexport_pwmchip1_channel
	# remove cache files
	if [[ -d "$CACHE_ROOT" ]]; then
		rm -rf "$CACHE_ROOT"
	fi
	echo '--------------------'
}

unexport_pwmchip1_channel () {
	if [[ -d "$CHANNEL_FOLDER" ]]; then
		echo '[pwm-fan] Freeing up the channel '$CHANNEL' controlled by the pwmchip1.'
		echo 0 > $CHANNEL_FOLDER'enable'
		sleep 1
		echo 0 > $PWMCHIP1_FOLDER'unexport'
		echo '[pwm-fan] Channel '$CHANNEL' was disabled.'
	else
		echo '[pwm-fan] There is no channel to disable.'
	fi
}

export_pwmchip1_channel () {
	if [[ ! -d "$CHANNEL_FOLDER" ]]; then
	    local EXPORT='/sys/class/pwm/pwmchip1/export'
	    cache 'export'
	    local EXPORT_SET=$(echo 0 2> "$CACHE" > "$EXPORT")
	    if [[ ! -z $(cat "$CACHE") ]]; then
	    	# on error, parse output
	    	if [[ $(cat "$CACHE") =~ (P|p)ermission\ denied ]]; then
	    		echo '[pwm-fan] This user does not have permission to use channel '$CHANNEL'.'
	    		# findout who owns export
	    		if [[ ! -z $(command -v stat) ]]; then
	    			echo '[pwm-fan] Export is owned by user: '$(stat -c '%U' "$EXPORT")'.'
    				echo '[pwm-fan] Export is owned by group: '$(stat -c '%G' "$EXPORT")'.'
	    		fi
	    		local ERR_MSG='User permission error while setting channel.'
	    	elif [[ $(cat "$CACHE") =~ (D|d)evice\ or\ resource\ busy ]]; then
	    		echo '[pwm-fan] It seems the pin is already in use. Cannot write to export.'
	    		local ERR_MSG='pwmchip1 was busy while setting channel.'
	    	else
	    		echo '[pwm-fan] There was an unknown error while setting the channel '$CHANNEL'.'
	    		if [[ $(cat "$CACHE") =~ \ ([^\:]+)$ ]]; then
	    			echo '[pwm-fan] Error: '${BASH_REMATCH[1]}'.'
	    		fi
	    		local ERR_MSG='Unknown error while setting channel.'
	    	fi
	    	end "$ERR_MSG" 1
	    fi
	    sleep 1
	elif [[ -d "$CHANNEL_FOLDER" ]]; then
		echo '[pwm-fan] '$CHANNEL' channel is already accessible.'
	fi
}

interrupt () {
	echo '!! ATTENTION !!'
	end 'Received a signal to stop the script.' 1
}

pwmchip1 () {
	PWMCHIP1_FOLDER='/sys/class/pwm/pwmchip1/'
	if [[ ! -d "$PWMCHIP1_FOLDER" ]]; then
		echo '[pwm-fan] The sysfs interface for the pwmchip1 is not accessible.'
		end 'Cannot access pwmchip1 sysfs interface.' 1
	fi
	echo '[pwm-fan] Working with the sysfs interface for the pwmchip1.'
	echo '[pwm-fan] For reference, your pwmchip1 supports '$(cat $PWMCHIP1_FOLDER'npwm')' channels.'
	# set channel for the pwmchip1
	CHANNEL="$1"
	if [[ -z "$CHANNEL" ]]; then
		# if no arg provided, assume ch 0
		CHANNEL='pwm0'
	fi
	CHANNEL_FOLDER="$PWMCHIP1_FOLDER""$CHANNEL"'/'
}

set_default () {
	cache 'set_default_duty_cycle'
	echo 0 2> $CACHE > $CHANNEL_FOLDER'duty_cycle'
	if [[ ! -z $(cat $CACHE) ]]; then
		# set higher than 0 values to avoid negative ones
		echo 100 > $CHANNEL_FOLDER'period'
		echo 10 > $CHANNEL_FOLDER'duty_cycle'
	fi
	cache 'set_default_period'
	echo $PERIOD 2> $CACHE > $CHANNEL_FOLDER'period'
	if [[ ! -z $(cat $CACHE) ]]; then
		echo '[pwm-fan] The period provided ('$PERIOD') is not acceptable.'
		echo '[pwm-fan] Trying to lower it by 100ns decrements. This may take a while...'
		local decrement=100
		local rate=$decrement
		until [[ $PERIOD_ -le 1 ]]; do
			local PERIOD_=$((PERIOD-rate))
			# if period goes too low, catch it and set to 1
			if [[ $PERIOD_ -lt 1 ]]; then
				local PERIOD_=1
			fi
			> $CACHE
			echo $PERIOD_ 2> $CACHE > $CHANNEL_FOLDER'period'
			if [[ -z $(cat $CACHE) ]]; then
				break
			fi
			local rate=$((rate+decrement))
		done
		PERIOD=$PERIOD_
		if [[ $PERIOD -le 100 ]]; then
			end 'Unable to set an appropriate value for the period.' 1
		fi
	fi
	# set polarity
	echo 'normal' > $CHANNEL_FOLDER'polarity'
	# let user know about default values
	echo '[pwm-fan] Default polarity set to '$(cat $CHANNEL_FOLDER'polarity')'.'
	echo '[pwm-fan] Default period set to '$(cat $CHANNEL_FOLDER'period')' ns.'
	echo '[pwm-fan] Default duty cycle set to '$(cat $CHANNEL_FOLDER'duty_cycle')' ns of active time.'
}

fan_startup () {
	PERIOD="$1"
	if [[ -z $PERIOD ]]; then
		# default period is 25kHz / 40000 nanoseconds
		PERIOD=40000
	elif [[ ! $PERIOD =~ ^[0-9]*$ ]]; then
		echo '[pwm-fan] The period must be an integer greater than 0.'
		end 'Period is not integer' 1
	fi
	while [[ -d "$CHANNEL_FOLDER" ]]; do
		if [[ $(cat $CHANNEL_FOLDER'enable') -eq 0 ]]; then
			# fan is not enabled
			set_default
			break
		elif [[ $(cat $CHANNEL_FOLDER'enable') -eq 0 ]]; then
			# fan is enabled
			echo '[pwm-fan] The fan is already enabled. Will disable it.'
			echo 0 > $CHANNEL_FOLDER'enable'
			sleep 1
			set_default
			break
		else
			echo '[pwm-fan] Unable to read the fan enable status.'
			end 'Bad fan status' 1
		fi
	done
}

# takes time (in seconds) to run at full speed
fan_initialization () {
	local TIME=$1
	if [[ -z "$TIME" ]]; then
		local TIME=10
	fi
	cache 'test_fan'
	local READ_MAX_DUTY_CYCLE=$(cat $CHANNEL_FOLDER'period')
	echo $READ_MAX_DUTY_CYCLE 2> $CACHE > $CHANNEL_FOLDER'duty_cycle'
	# on error, try setting duty_cycle to a lower value
	if [[ ! -z $(cat $CACHE) ]]; then
		local READ_MAX_DUTY_CYCLE=$(cat $CHANNEL_FOLDER'period')-100
		> $CACHE
		echo $READ_MAX_DUTY_CYCLE 2> $CACHE > $CHANNEL_FOLDER'duty_cycle'
		if [[ ! -z $(cat $CACHE) ]]; then
			end 'Unable to set max duty_cycle.' 1
		fi
	fi
	echo '[pwm-fan] Running fan at full speed for the next '$TIME' seconds...'
	echo 1 > $CHANNEL_FOLDER'enable'
	sleep $TIME
	# keep it running at half period
	echo $((READ_MAX_DUTY_CYCLE/2)) > $CHANNEL_FOLDER'duty_cycle'
	echo '[pwm-fan] Initialization done. Duty cycle at 25% now: '$((READ_MAX_DUTY_CYCLE/4))' ns.'
}

# takes channel (pwmN) and period (integer in ns) as arg
config () {
	pwmchip1 "$1"
	export_pwmchip1_channel
	fan_startup "$2"
	fan_initialization 5
}

# run pwm-fan
start
trap 'interrupt' SIGINT SIGHUP SIGTERM SIGKILL
# user may provide custom period as first arg
config pwm0 $1
end 'Finished without any errors' 0

# CPU temps to monitor
declare -a CpuTemps=(75000 65000 55000 40000 25000 0)
# Duty cycle for each CPU temp range
declare -a DutyCycles=(39990 6000 3000 2000 1500 0)

# Main loop to monitor cpu temp and assign duty cycles accordingly
while true
do
	temp0=$(cat /sys/class/thermal/thermal_zone0/temp)
	# If you changed the length of $CpuTemps and $DutyCycles, then change the following length, too
	for i in 0 1 2 3 4 5; do
		if [ $temp0 -gt ${CpuTemps[$i]} ]; then
			DUTY=${DutyCycles[$i]}
			echo $DUTY > "/sys/class/pwm/pwmchip1/pwm0/duty_cycle";
			# To test the script, uncomment the following:
			#echo "temp: $temp0, target: ${CpuTemps[$i]}, duty: $DUTY"
			break		
		fi
	done
	# Change the following if you want the script to change the fan speed more/less frequently
	sleep 10s;
done

exit 0
