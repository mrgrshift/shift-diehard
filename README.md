#shift-diehard

**The current version is alpha, try it at your own risk**<br>

Tool to manage the status of your server, this tool is prepared for Shift versions 5x and 6x.<br>
<br>
#Requisites
    - You need to have Shift installed : https://github.com/shiftcurrency/shift
    - Start your Shift instance with: forever start app.js
    - Remove your passphrase from your shift/config.json
    - Edit diehard_config.json file according to your delegate
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
You need to run it in a separated process.<br>
You can see what it is doing in the logs/ folder. `diehard.log` is the main log file. `diehard_check.log` is where cron leaves its log.<br>
