#!/bin/bash

############################################################################
# Bash script to control the NanoPi M4 SATA hat fan via the sysfs interface
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
		sleep 1
		if [[ ! -d "$CHANNEL_FOLDER" ]]; then
			echo '[pwm-fan] Channel '$CHANNEL' was disabled.'
		else
			echo '[pwm-fan] Channel '$CHANNEL' is still enabled. Please check '$CHANNEL_FOLDER'.'
		fi
	else
		echo '[pwm-fan] There is no channel to disable.'
	fi
}

export_pwmchip1_channel () {
	if [[ ! -d "$CHANNEL_FOLDER" ]]; then
	    local EXPORT=$PWMCHIP1_FOLDER'export'
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
	end 'Received a signal to stop the script.' 0
}

pwmchip1 () {
	PWMCHIP1_FOLDER='/sys/class/pwm/pwmchip1/'
	if [[ ! -d "$PWMCHIP1_FOLDER" ]]; then
		echo '[pwm-fan] The sysfs interface for the pwmchip1 is not accessible.'
		end 'Cannot access pwmchip1 sysfs interface.' 1
	fi
	echo '[pwm-fan] Working with the sysfs interface for the pwmchip1.'
	echo '[pwm-fan] For reference, your pwmchip1 supports '$(cat $PWMCHIP1_FOLDER'npwm')' channel(s).'
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
	# set global max duty cycle
	MAX_DUTY_CYCLE=$READ_MAX_DUTY_CYCLE
	echo '[pwm-fan] Running fan at full speed for the next '$TIME' seconds...'
	echo 1 > $CHANNEL_FOLDER'enable'
	sleep $TIME
	# keep it running at 25% period
	echo $((MAX_DUTY_CYCLE/2)) > $CHANNEL_FOLDER'duty_cycle'
	echo '[pwm-fan] Initialization done. Duty cycle at 25% now: '$((MAX_DUTY_CYCLE/4))' ns.'
}

thermal_monit () {
	local MONIT_DEVICE=$1
	if [[ -z $MONIT_DEVICE ]]; then
		# assume soc
		local MONIT_DEVICE='soc'
	fi
	local THERMAL_FOLDER='/sys/class/thermal/'
	if [[ -d $THERMAL_FOLDER ]]; then
		local ZONES=('thermal_zone0/' 'thermal_zone1/' 'thermal_zone2/' 'thermal_zone3/')
		for zone in ${ZONES[@]}; do
			if [[ -d $THERMAL_FOLDER$zone ]]; then
				if [[ $(cat $THERMAL_FOLDER$zone'type') =~ $MONIT_DEVICE ]]; then
					# temp in millidegree Celsius
					TEMP_FILE=$THERMAL_FOLDER$zone'temp'
					TEMP=$(cat $TEMP_FILE)
					echo '[pwm-fan] Found the '$MONIT_DEVICE' temperature at '$TEMP_FILE
					echo '[pwm-fan] Current '$MONIT_DEVICE' temp is: '$((TEMP/1000))' Celsius'
					echo '[pwm-fan] Setting fan to monitor the '$MONIT_DEVICE' temperature.'
					THERMAL_STATUS=1
					return
				fi
			fi
		done
	else
		echo '[pwm-fan] Sys interface for the thermal zones cannot be found at '$THERMAL_FOLDER
	fi
	echo '[pwm-fan] Setting fan to operate independent of the '$MONIT_DEVICE' temperature.'
	THERMAL_STATUS=0
}

fan_run () {
	if [[ $THERMAL_STATUS -eq 0 ]]; then
		echo '[pwm-fan] Running fan at full speed until stopped (Ctrl+C or kill '$$')...'
		while [[ true ]]; do
			echo $MAX_DUTY_CYCLE > $CHANNEL_FOLDER'duty_cycle'
		done
	else
		echo '[pwm-fan] Running fan in temp monitor mode until stopped (Ctrl+C or kill '$$')...'
		# TODO: select fancontrol algorithm
		# temp thresholds ?
		# TODO: Write a fancontrol algorithm based on average temp and temp change over time.
		# TODO: This should be more reliable than fixed values but set thresholds for both fan speed
		# TODO: (because the fan will stop spinning if the duty cycle is too low) and temperature 
		while [[ true ]]; do
			# infinite loop here
		done
	fi
}

# takes channel (pwmN) and period (integer in ns) as arg
config () {
	pwmchip1 "$1"
	export_pwmchip1_channel
	fan_startup "$2"
	fan_initialization 5
	thermal_monit "soc"
}

# run pwm-fan
start
trap 'interrupt' SIGINT SIGHUP SIGTERM SIGKILL
# user may provide custom period (in nanoseconds) as arg to the script
config pwm0 $1
# TODO: allow user to select fancontrol algorithm (fixed table vs dynamic)
fan_run
