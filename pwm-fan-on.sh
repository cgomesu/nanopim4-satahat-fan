#!/bin/bash

###########################################################################
# A simple bash script to run and control the NanoPi M4 SATA hat PWM1 fan #
###########################################################################

# Modified from mar0ni's script:
# https://forum.armbian.com/topic/11086-pwm-fan-on-nanopi-m4/?tab=comments#comment-95180 

# Export pwmchip1 that controls the SATA hat fan if it hasn't been done yet
# This will create a 'pwm0' subfolder that allows us to control various properties of the fan
if [ ! -d /sys/class/pwm/pwmchip1/pwm0 ]; then
    echo 0 > /sys/class/pwm/pwmchip1/export
fi
sleep 1
while [ ! -d /sys/class/pwm/pwmchip1/pwm0 ];
do
    sleep 1
done

# Set default period (40000ns = 25kHz)
echo 40000 > /sys/class/pwm/pwmchip1/pwm0/period

# The default polarity is inversed. Set it to 'normal' instead.
echo normal > /sys/class/pwm/pwmchip1/pwm0/polarity

# Run fan at full speed for 10s when the script starts and keep running at low speed
echo 40000 > /sys/class/pwm/pwmchip1/pwm0/duty_cycle
echo 1 > /sys/class/pwm/pwmchip1/pwm0/enable
sleep 10
echo 1500 > /sys/class/pwm/pwmchip1/pwm0/duty_cycle

# CPU temps to monitor
declare -a CpuTemps=(75000 65000 55000 40000 25000 0)
# Duty cycle for each CPU temp range
declare -a DutyCycles=(40000 6000 3000 2000 1500 0)

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
