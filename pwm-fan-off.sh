#!/bin/bash

###########################################################################
# A simple bash script to run and control the NanoPi M4 SATA hat PWM1 fan #
###########################################################################

# Modified from mar0ni's script:
# https://forum.armbian.com/topic/11086-pwm-fan-on-nanopi-m4/?tab=comments#comment-95180 

# If running as service, execute this upon stop (ExecStop=)

# Disable a fan with normal polarity 
echo 0 > "/sys/class/pwm/pwmchip1/pwm0/enable"

exit 0

