# nanopim4-satahat-fan
Bash scripts to control the **[2-PIN PH2.0 12v fan connector from the Nano Pi M4 SATA hat](http://wiki.friendlyarm.com/wiki/index.php/NanoPi_M4_SATA_HAT)** with a systemd implementation to run the as a simple background service. I added comments to each script that might help you change it according to your needs, especially the fan `period` and `duty_cycle`.

# Authorship
This is a slightly modified version of **[mar0ni's script](https://forum.armbian.com/topic/11086-pwm-fan-on-nanopi-m4/?tab=comments#comment-95180)**.

# Installation
```
apt-get update
apt-get install git
cd /opt
git clone https://github.com/cgomesu/nanopim4-satahat-fan.git
cd nanopim4-satahat-fan
# Allow the ON and OFF scripts to be executed
chmod +x pwm-fan-on.sh
chmod +x pwm-fan-off.sh
# Test run the ON script
bash pwm-fan-on.sh
# Press ctrl+c after a few seconds to send a SIGINT and stop the script
# Test run the OFF script to disable the fan
bash pwm-fan-off.sh
```

# Run it as a service
```
# Copy the pwm-fan.service file to your systemd folder
cp /opt/nanopim4-satahat-fan/pwm-fan.service /lib/systemd/system/
# Enable the service and start it
systemctl enable pwm-fan.service
systemctl start pwm-fan.service
# Check the service status to make sure it's running without issues
systemctl status pwm-fan.service
# Make sure the OFF script is running corrently when the service is stopped
systemctl stop pwm-fan.service
# Then start the service again
systemctl start pwm-fan.service
```
If you have permission issues, use a sudo user and add `sudo` before each command
