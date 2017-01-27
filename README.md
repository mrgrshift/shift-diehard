#shift-diehard

Tool to manage the status of your server.<br>

**The current version is alpha, try it at your own risk**<br>

<br>
#Requisites
    - You need to have Shift installed : https://github.com/shiftcurrency/shift
    - Stop your Shift instance, this script will manage the start and stop app.js
    - You need to have jq installed: sudo apt-get install jq

#Installation
Just do the following:
```
cd ~/
git clone https://github.com/mrgrshift/shift-diehard
cd shift-diehard/
bash shift-diehard.sh install
```
After you finish the installation process run: `bash shift-diehard.sh start`<br>
You need to run it in a separated process.Use `screen -S diehard` then `bash shift-diehard.sh start`, here is a [screen quick reference] (http://aperiodic.net/screen/quick_reference).<br>
You can see what it is doing in the logs/ folder. `diehard.log` is the main log file. `diehard_check.log` is where cron leaves its log.<br>
