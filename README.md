# nanopim4-satahat-fan
A fan control script in Bash for the [**2-pin PH2.0 12v fan connector of the NanoPi M4 SATA hat**](http://wiki.friendlyarm.com/wiki/index.php/NanoPi_M4_SATA_HAT). By default, the script uses a bounded [logistic model](https://en.wikipedia.org/wiki/Logistic_function) with a moving mid-point (based on the average temperature over time) to set the fan speed. 

Many of the variables use in this fan controller can be modified directly from the CLI, such as setting custom temperature thresholds (`-t`, `-T`) or disabling temperature monitoring altogether (`-f`). For a more detailed description, see [**Usage**](#usage).

There's arguably more code here than necessary to run a fan controller. This was a hobbie of mine (I wanted to revisit the first version which used a fixed table to set speed) and an opportunity to learn more about Bash and the sysfs interface.  

If you have any issues or suggestions, open an issue or [send me an e-mail](mailto:me@cgomesu.com).


# Requisites
- GNU bash;
- Access to the [pwm sysfs interface](https://www.kernel.org/doc/Documentation/pwm.txt);
- Standard Linux commands.

You don't need to check any of this manually. The script will automatically check for everything it needs to run and will let you know if there's any errors or missing access to important commands.  

The controller was developed with Armbian OS but you should be able to run it on any other Linux distro for the NanoPi M4. For reference, this script was originally developed with the following hardware:
-  NanoPi-M4 v2
-  M4 SATA hat
-  Generic 12V (0.2A) fan

And software:
-  Kernel: Linux 4.4.231-rk3399
-  OS: Armbian Buster (20.08.9) stable
-  GNU bash v5.0.3
-  bc v1.07.1


# Installation
```
apt-get update
apt-get install git
cd /opt

# From now on, if you're not running as root, append 'sudo' if you run into permission issues
git clone https://github.com/cgomesu/nanopim4-satahat-fan.git
cd nanopim4-satahat-fan

# Allow the script to be executed
chmod +x pwm-fan.sh

# Test the script
./pwm-fan.sh

# Check for any error messages 
# When done, press Ctrl+C after to send a SIGINT and stop the script
```


# Usage
```
./pwm-fan.sh -h
```
```
Usage:

./pwm-fan.sh [OPTIONS]

  Options:
    -c  st  Name of the PWM CHANNEL (e.g., pwm0, pwm1). Default: pwm0
    -C  st  Name of the PWM CONTROLLER (e.g., pwmchip0, pwmchip1). Default: pwmchip1
    -d  in  Lowest DUTY CYCLE threshold (in percentage of the period). Default: 25
    -D  in  Highest DUTY CYCLE threshold (in percentage of the period). Default: 100
    -f      Fan runs at FULL SPEED all the time. If omitted (default), speed depends on temperature.
    -F  in  TIME (in seconds) to run the fan at full speed during STARTUP. Default: 60
    -h      Show this HELP message.
    -l  in  TIME (in seconds) to LOOP thermal reads. Lower means higher resolution but uses ever more resources. Default: 10
    -m  st  Name of the DEVICE to MONITOR the temperature in the thermal sysfs interface. Default: soc
    -p  in  The fan PERIOD (in nanoseconds). Default (30kHz): 30000000.
    -s  in  The MAX SIZE of the TEMPERATURE ARRAY. Interval between data points is set by -l. Default (store last 1min data): 6.
    -t  in  Lowest TEMPERATURE threshold (in Celsius). Lower temps set the fan speed to min. Default: 25
    -T  in  Highest TEMPERATURE threshold (in Celsius). Higher temps set the fan speed to max. Default: 75

  If no options are provided, the script will run with default values.
  Defaults have been tested and optimized for the following hardware:
    -  NanoPi-M4 v2
    -  M4 SATA hat
    -  Fan 12V (.08A)
  And software:
    -  Kernel: Linux 4.4.231-rk3399
    -  OS: Armbian Buster (20.08.9) stable
    -  GNU bash v5.0.3
    -  bc v1.07.1

Author: cgomesu
Repo: https://github.com/cgomesu/nanopim4-satahat-fan

This is free. There is NO WARRANTY. Use at your own risk.

```


# Run in the Background
```
# Copy the pwm-fan.service file to your systemd folder
cp /opt/nanopim4-satahat-fan/pwm-fan.service /lib/systemd/system/

# Enable the service and start it
systemctl enable pwm-fan.service
systemctl start pwm-fan.service

# Check the service status to make sure it's running without issues
systemctl status pwm-fan.service
```
