#!/bin/bash

############################################################################
# Bash script to control the NanoPi M4 SATA hat PWM1 fan via sysfs interface
############################################################################
# Officila sysfs doc:
# https://www.kernel.org/doc/Documentation/pwm.txt
###########################################################################

start () {
	echo '##############################################'
	echo '# STARTING PWM-FAN SCRIPT'
	echo '##############################################'
}

# accept message and status as argument
end () {
	cleanup
	echo '##############################################'
	echo '# END OF THE PWM-FAN SCRIPT'
	echo '# MESSAGE: '$1
	echo '##############################################'
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
	# TODO: stop and free up used pins
	# remove cache files
	if [[ -d "$CACHE_ROOT" ]]; then
		rm -rf "$CACHE_ROOT"
	fi
}

unexport_pwmchip1_channel () {
	if [[ -d "$CHANNEL_FOLDER" ]]; then
	    local UNEXPORT='/sys/class/pwm/pwmchip1/unexport'
	    cache 'unexport'
	    # TODO: Disable pin first then unexport
	    local UNEXPORT_SET=$(echo 0 2> "$CACHE" > "$UNEXPORT")
	    # TODO: Handle unexport errors
	elif [[ ! -d "$CHANNEL_FOLDER" ]]; then
		echo '[pwm-fan] It seems channel '$CHANNEL' has already been freed up or is not controlled by pwmchip1.'
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
	    		echo '[pwm-fan] This user does not have permission to use channel '$CHANNEL
	    		# findout who owns export
	    		if [[ ! -z $(command -v stat) ]]; then
	    			echo '[pwm-fan] Export is owned by user: '$(stat -c '%U' "$EXPORT")
    				echo '[pwm-fan] Export is owned by group: '$(stat -c '%G' "$EXPORT")
	    		fi
	    		local ERR_MSG='User permission error while setting channel.'
	    	elif [[ $(cat "$CACHE") =~ (D|d)evice\ or\ resource\ busy ]]; then
	    		echo '[pwm-fan] It seems the pin is already in use. Cannot write to export.'
	    		local ERR_MSG='pwmchip1 was busy while setting channel.'
	    	else
	    		echo '[pwm-fan] There was an unknown error while setting the channel '$CHANNEL
	    		if [[ $(cat "$CACHE") =~ \ ([^\:]+)$ ]]; then
	    			echo '[pwm-fan] Error: '${BASH_REMATCH[1]}
	    		fi
	    		local ERR_MSG='Unknown error while setting channel.'
	    	fi
	    	end "$ERR_MSG" 1
	    fi
	    sleep 1
	elif [[ -d "$CHANNEL_FOLDER" ]]; then
		echo '[pwm-fan] '$CHANNEL' channel is already accessible'
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
	SET_DUTY_CYCLE=$(echo 0 2> $CACHE > $CHANNEL_FOLDER'duty_cycle')
	if [[ ! -z $(cat $CACHE) ]]; then
		echo 'bad set_duty_cycle'
		SET_PERIOD=$(echo 1000 > $CHANNEL_FOLDER'period')
		SET_DUTY_CYCLE=$(echo 0 > $CHANNEL_FOLDER'duty_cycle')
	fi
	cache 'set_default_period'
	SET_PERIOD=$(echo $PERIOD 2> $CACHE > $CHANNEL_FOLDER'period')
	if [[ ! -z $(cat $CACHE) ]]; then
		echo '[pwm-fan] The period provided ('$PERIOD') is not acceptable.'
		echo '[pwm-fan] Trying to lower it by 100ns decrements. This may take a while.'
		local PERIOD_=$PERIOD
		local rate=100
		local decrement=$rate
		until [[ $PERIOD_ -le 1 ]]; do
			local PERIOD_=$(($PERIOD-$decrement))
			if [[ $PERIOD_ -lt 1 ]]; then
				local PERIOD_=1
			fi
			echo $PERIOD_
			> $CACHE
			SET_PERIOD=$(echo $PERIOD_ 2> $CACHE > $CHANNEL_FOLDER'period')
			if [[ -z $CACHE ]]; then
				break
			fi
			local decrement=$((decrement+$rate))
		done
		PERIOD=$PERIOD_
		if [[ $PERIOD -le 50 ]]; then
			end 'Unable to set an appropriate value for the period' 1
		fi
		echo '[pwm-fan] Current period is now '$PERIOD
	fi
	SET_POLARITY=$(echo 'normal' > $CHANNEL_FOLDER'polarity')
	READ_POLARITY=$(cat $CHANNEL_FOLDER'polarity')
	READ_PERIOD=$(cat $CHANNEL_FOLDER'period')
	READ_DUTY_CYCLE=$(cat $CHANNEL_FOLDER'duty_cycle')
	echo '[pwm-fan] Default polarity was set to: '$READ_POLARITY
	echo '[pwm-fan] Default period was set to: '$READ_PERIOD' ns'
	echo '[pwm-fan] Default duty cycle was set to: '$READ_DUTY_CYCLE' ns of active time'
}

# TODO: need to finish this function
fan_startup () {
	PERIOD="$1"
	if [[ -z $PERIOD ]]; then
		# default period is 25kHz / 40000 nanoseconds
		PERIOD=40000
	elif [[ ! $PERIOD =~ ^[0-9]*$ ]]; then
		echo '[pwm-fan] The period must be an integer greater than 0.'
		end 'Period is not integer' 1
	fi
	while [[ ! $CONFIG_READY && -d "$CHANNEL_FOLDER" ]]; do
		READ_ENABLE=$(cat $CHANNEL_FOLDER'enable')
		if [[ $READ_ENABLE -eq 0 ]]; then
			# fan is not enabled
			set_default
			CONFIG_READY=1
		elif [[ $READ_ENABLE -eq 0 ]]; then
			# fan is enabled
			echo '[pwm-fan] The fan is already enabled. Will disable it.'
			SET_ENABLE=$(echo 0 > $CHANNEL_FOLDER'enable')
			sleep 1
			set_default
			CONFIG_READY=1
		else
			echo '[pwm-fan] Unable to read the fan enable status.'
			end 'Bad fan status' 1
		fi
	done
}

# takes channel (pwmN) and period (integer in ns) as arg
config () {
	pwmchip1 "$1"
	export_pwmchip1_channel
	fan_startup "$2"
}

# run pwm-fan
start
trap 'interrupt' SIGINT SIGHUP SIGTERM SIGKILL
# user may provide custom period as first arg
config pwm0 $1
end 'Finished without any errors' 0


# Set default period (40000ns = 25kHz)
echo 40000 > /sys/class/pwm/pwmchip1/pwm0/period

# The default polarity is inversed. Set it to 'normal' instead.
echo normal > /sys/class/pwm/pwmchip1/pwm0/polarity

# Run fan at full speed for 10s when the script starts and keep running at low speed
echo 39990 > /sys/class/pwm/pwmchip1/pwm0/duty_cycle
echo 1 > /sys/class/pwm/pwmchip1/pwm0/enable
sleep 10
echo 1500 > /sys/class/pwm/pwmchip1/pwm0/duty_cycle

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
