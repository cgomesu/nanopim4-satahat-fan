#!/bin/bash

###############################################################################
# Bash script to control the NanoPi M4 SATA hat 12v fan via the sysfs interface
###############################################################################
# Official pwm sysfs doc:
# https://www.kernel.org/doc/Documentation/pwm.txt
###############################################################################

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
	unexport_pwmchip_channel
	# remove cache files
	if [[ -d "$CACHE_ROOT" ]]; then
		rm -rf "$CACHE_ROOT"
	fi
	echo '--------------------'
}

# takes channel (pwmN) and period (integer in ns) as arg
config () {
	pwmchip "$1" "$2"
	export_pwmchip_channel
	fan_startup "$3"
	fan_initialization 5 #time in seconds for initial run at full speed
	thermal_monit "soc"
}

# takes message and status as argument
end () {
	cleanup
	echo '####################################################'
	echo '# END OF THE PWM-FAN SCRIPT'
	echo '# MESSAGE: '$1
	echo '####################################################'
	exit $2
}

export_pwmchip_channel () {
	if [[ ! -d "$CHANNEL_FOLDER" ]]; then
	    local EXPORT=$PWMCHIP_FOLDER'export'
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
	    		local ERR_MSG=$PWMCHIP' was busy while setting channel.'
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
	echo '[pwm-fan] Initialization done. Duty cycle at 50% now: '$((MAX_DUTY_CYCLE/2))' ns.'
	sleep 1
}

fan_run () {
	if [[ $THERMAL_STATUS -eq 0 ]]; then
		fan_run_max
	else
		fan_run_thermal
	fi
}

fan_run_max () {
	echo '[pwm-fan] Running fan at full speed until stopped (Ctrl+C or kill '$$')...'
	while true; do
		echo $MAX_DUTY_CYCLE > $CHANNEL_FOLDER'duty_cycle'
		# run every so often to make sure it is max
		sleep 120
	done
}

fan_run_thermal () {
	echo '[pwm-fan] Running fan in temp monitor mode until stopped (Ctrl+C or kill '$$')...'
	THERMAL_ABS_THRESH=(25 35 50 65 75)
	# to prevent from stop spinning, never go lower than 25% after the startup
	DC_ABS_THRESH=($((MAX_DUTY_CYCLE/4)) $((MAX_DUTY_CYCLE/2)) $(((3*MAX_DUTY_CYCLE)/4)) $MAX_DUTY_CYCLE)
	# THERMAL_DELTA_THRESH=(5 15 25)
	# DC_DELTA_MULTIPLIER=(1 2 3)
	TEMPS=()
	# loop*max_temps gives an approximate time range of the stored temps
	MAX_TEMPS=6 #number of temperatures to keep in the TEMPS array
	LOOP_TIME=10 #in seconds, lower means higher resolution
	while true ; do
		TEMPS+=($(thermal_meter))
		if [[ ${#TEMPS[@]} -gt $MAX_TEMPS ]]; then
			TEMPS=(${TEMPS[@]:1})
		fi
		# TODO: Remove debugging messages when done
		if [[ ${TEMPS[-1]} -le ${THERMAL_ABS_THRESH[0]} ]]; then
			echo 'set duty cycle to MIN DC: '${DC_ABS_THRESH[0]}
			echo ${DC_ABS_THRESH[0]} 2> /dev/null > $CHANNEL_FOLDER'duty_cycle'
		elif [[ ${TEMPS[-1]} -ge ${THERMAL_ABS_THRESH[-1]} ]]; then
			echo 'set duty cycle to MIN DC: '${DC_ABS_THRESH[-1]}
			echo ${DC_ABS_THRESH[-1]} 2> /dev/null > $CHANNEL_FOLDER'duty_cycle'
		elif [[ ${#TEMPS[@]} -gt 1 ]]; then
			# compute mean temp
			TEMPS_SUM=0
			for TEMP in ${TEMPS[@]}; do
	                let TEMPS_SUM+=$TEMP
	        done
	        MEAN_TEMP=$((TEMPS_SUM/${#TEMPS[@]}))
			# moving mid-point based on inversed mean
			X0=$(($MEAN_TEMP-100))
			# args: x, x0, L, a, b (k=a/b)
			MODEL=$(function_logistic ${TEMPS[-1]} ${X0#-} ${DC_ABS_THRESH[-1]} 1 10)
			if [[ $MODEL -lt ${DC_ABS_THRESH[0]} ]]; then
				echo 'set duty cycle to '${DC_ABS_THRESH[0]}
				echo ${DC_ABS_THRESH[0]} 2> /dev/null > $CHANNEL_FOLDER'duty_cycle'
			elif [[ $MODEL -gt ${DC_ABS_THRESH[-1]} ]]; then
				echo 'set duty cycle to '${DC_ABS_THRESH[-1]}
				echo ${DC_ABS_THRESH[-1]} 2> /dev/null > $CHANNEL_FOLDER'duty_cycle'
			else
				echo 'set duty cycle to '$MODEL
				echo $MODEL 2> /dev/null > $CHANNEL_FOLDER'duty_cycle'
			fi
		# let first run do nothing
		fi
		sleep $LOOP_TIME
	done
}

fan_startup () {
	PERIOD="$1"
	if [[ -z $PERIOD ]]; then
		# default period is 30000000 nanoseconds 30kHz
		PERIOD=30000000
	elif [[ ! $PERIOD =~ ^[0-9]*$ ]]; then
		echo '[pwm-fan] The period must be an integer greater than 0.'
		end 'Period is not integer' 1
	fi
	while [[ -d "$CHANNEL_FOLDER" ]]; do
		if [[ $(cat $CHANNEL_FOLDER'enable') -eq 0 ]]; then
			set_default
			break
		elif [[ $(cat $CHANNEL_FOLDER'enable') -eq 1 ]]; then
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

function_logistic () {
        # https://en.wikipedia.org/wiki/Logistic_function
        local x=$1
        local x0=$2
        local L=$3
        # k=a/b
        local a=$4
        local b=$5
        local equation="output=$L/(1+e(-($a/$b)*($x-$x0)));scale=0;output/1"
        local result=$(echo $equation | bc -lq)
        echo $result
}

interrupt () {
	echo '!! ATTENTION !!'
	end 'Received a signal to stop the script.' 0
}

# takes chip and channel as arg
pwmchip () {
	PWMCHIP=$1
	if [[ -z $PWMCHIP ]]; then
		# if no arg, assume 1
		PWMCHIP='pwmchip1'
	fi
	PWMCHIP_FOLDER='/sys/class/pwm/'$PWMCHIP'/'
	if [[ ! -d "$PWMCHIP_FOLDER" ]]; then
		echo '[pwm-fan] The sysfs interface for the '$PWMCHIP' is not accessible.'
		end 'Cannot access '$PWMCHIP' sysfs interface.' 1
	fi
	echo '[pwm-fan] Working with the sysfs interface for the '$PWMCHIP'.'
	echo '[pwm-fan] For reference, your '$PWMCHIP' supports '$(cat $PWMCHIP_FOLDER'npwm')' channel(s).'
	# set channel for the pwmchip
	CHANNEL="$2"
	if [[ -z $CHANNEL ]]; then
		# if no arg provided, assume ch 0
		CHANNEL='pwm0'
	fi
	CHANNEL_FOLDER="$PWMCHIP_FOLDER""$CHANNEL"'/'
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
		until [[ $PERIOD_NEW -le 200 ]]; do
			local PERIOD_NEW=$((PERIOD-rate))
			> $CACHE
			echo $PERIOD_NEW 2> $CACHE > $CHANNEL_FOLDER'period'
			if [[ -z $(cat $CACHE) ]]; then
				break
			fi
			local rate=$((rate+decrement))
		done
		PERIOD=$PERIOD_NEW
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

start () {
	echo '####################################################'
	echo '# STARTING PWM-FAN SCRIPT'
	echo '# Date and time: '$(date)
	echo '####################################################'
}

thermal_meter () {
	if [[ -f $TEMP_FILE ]]; then
		local TEMP=$(cat $TEMP_FILE 2> /dev/null)
		# TEMP is in millidegrees, so convert to degrees
		echo $((TEMP/1000))
	fi
}

thermal_monit () {
	local MONIT_DEVICE=$1
	if [[ -z $MONIT_DEVICE ]]; then
		# assume soc
		local MONIT_DEVICE='soc'
	fi
	local THERMAL_FOLDER='/sys/class/thermal/'
	if [[ -d $THERMAL_FOLDER ]]; then
		for dir in $THERMAL_FOLDER'thermal_zone'*; do
			if [[ $(cat $dir'/type') =~ $MONIT_DEVICE && -f $dir'/temp' ]]; then
				TEMP_FILE=$dir'/temp'
				echo '[pwm-fan] Found the '$MONIT_DEVICE' temperature at '$TEMP_FILE
				echo '[pwm-fan] Current '$MONIT_DEVICE' temp is: '$(($(thermal_meter)))' Celsius'
				echo '[pwm-fan] Setting fan to monitor the '$MONIT_DEVICE' temperature.'
				THERMAL_STATUS=1
				return
			fi
		done
		echo '[pwm-fan] Did not find the temperature for the device type: '$MONIT_DEVICE
	else
		echo '[pwm-fan] Sys interface for the thermal zones cannot be found at '$THERMAL_FOLDER
	fi
	echo '[pwm-fan] Setting fan to operate independent of the '$MONIT_DEVICE' temperature.'
	THERMAL_STATUS=0
}

unexport_pwmchip_channel () {
	if [[ -d "$CHANNEL_FOLDER" ]]; then
		echo '[pwm-fan] Freeing up the channel '$CHANNEL' controlled by the '$PWMCHIP'.'
		echo 0 > $CHANNEL_FOLDER'enable'
		sleep 1
		echo 0 > $PWMCHIP_FOLDER'unexport'
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

# TODO: use getopts instead for named args
# run pwm-fan
start
trap 'interrupt' SIGINT SIGHUP SIGTERM SIGKILL
# user may provide custom period (in nanoseconds) as arg to the script
config 'pwmchip1' 'pwm0' "$1"
# TODO: allow user to select fancontrol algorithm (fixed table vs dynamic)
fan_run
