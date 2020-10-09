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
	# remove cache files
	if [[ -d "$CACHE_ROOT" ]]; then
		rm -rf "$CACHE_ROOT"
	fi
}

unexport_pwmchip1_channel () {
	# set channel for the pwmchip1
	local CHANNEL="$1"
	if [[ -z "$CHANNEL" ]]; then
		# if no arg provided, assume ch 0
		local CHANNEL='pwm0'
	fi
	PWMCHIP1_FOLDER='/sys/class/pwm/pwmchip1/'
	CHANNEL_FOLDER="$PWMCHIP1_FOLDER""$CHANNEL"'/'
	if [[ -d "$CHANNEL_FOLDER" ]]; then
	    local UNEXPORT='/sys/class/pwm/pwmchip1/unexport'
	    cache 'unexport'
	    # TODO: Disable pin first then unexport
	    local UNEXPORT_SET=$(echo 0 2> "$CACHE" > "$UNEXPORT")
	    # TODO: Handle unexport errors
	elif [[ ! -d "$CHANNEL_FOLDER" ]]; then
		echo '[pwm-fan] It seems channel '$CHANNEL' has already been freed up or is not controlled by pwmchip1.'
		echo '[pwm-fan] For reference, pwmchip1 supports '$(cat $PWMCHIP1_FOLDER'npwm')' channels'
	fi
}

# accept channel as argument
export_pwmchip1_channel () {
	# set channel for the pwmchip1
	CHANNEL="$1"
	if [[ -z "$CHANNEL" ]]; then
		# if no arg provided, assume ch 0
		CHANNEL='pwm0'
	fi
	PWMCHIP1_FOLDER='/sys/class/pwm/pwmchip1/'
	CHANNEL_FOLDER="$PWMCHIP1_FOLDER""$CHANNEL"'/'
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

fan_startup () {
	if [[ -z "$CHANNEL" || -z "$CHANNEL_FOLDER" ]]; then
		echo '[pwm-fan] Something is wrong. The channel has not been set before.'
		end 'Trying to start the fan without a channel.' 1
	fi
	while [[ ! $ERR_CONFIG && -d "$CHANNEL_FOLDER" ]]; do
		local READ_ENABLE=$(cat $CHANNEL_FOLDER'enable')
		local READ_PERIOD=$(cat $CHANNEL_FOLDER'period')
		local READ_DUTY_CYCLE=$(cat $CHANNEL_FOLDER'duty_cycle')
		local READ_POLARITY=$(cat $CHANNEL_FOLDER'polarity')
	done
}

config () {
	export_pwmchip1_channel pwm0
	fan_startup
}

config 



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
