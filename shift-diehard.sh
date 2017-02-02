#!/bin/bash
VERSION="Diehard"

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8

# Diehard script to monitor your Shift node.
# Don't forget to vote for mrgr delegate.
#============================================================

# Requisites:
# - Start your Shift installation with: forever start app.js



DIEHARD_HOME=$(pwd)

					
install_diehard(){
  OK="0"
  if [ -f "diehard_conf.json" ]; then
	OK="1"
	read -p "**A previous installation was detected, do you want to proceed anyway (y/n)?" -n 1 -r
	if [[  $REPLY =~ ^[Nn]$ ]]
	   then
		OK=0
	fi
  fi
  if [ "$OK" -eq "0" ]; then
	echo "*****************************"
	echo "Diehard installation.."
	echo "Important information before you install. This script will handle your Shift instance, automaticly will perform forever start app.js and forever stop app.js so please stop your Shift instance before starting this script."
	echo
	echo -n "Confirm the path of your Shift installation? (leave empty to choose default /home/$USER/shift/ ) :"
	read SHIFT_PATH
	if [ "$SHIFT_PATH" == "" ]; then
	   SHIFT_PATH="/home/$USER/shift/"
	fi
	echo
	echo -n "Enter your delegate name: "
	read DELEGATE_NAME
	echo -n "Enter your dlegate address: "
        read DELEGATE_ADDRESS
	echo -n "Enter your delegate passphrase: "
	read SECRET
	echo
	echo "If you have a backup server enter the following information, if not just press enter."
        echo -n "Backup IP: "
        read BACKUP_IP
        echo -n "Backup Port: "
        read BACKUP_PORT

	echo
  	mkdir -p snapshot
  	mkdir -p logs
  	sudo chmod a+x shift-diehard.sh
  	sudo chown postgres:${USER:=$(/usr/bin/id -run)} snapshot
  	sudo chmod -R 777 snapshot
  	sudo chmod -R 777 logs

	jqinstalled=$(dpkg-query -l 'jq' | grep "jq")
	if [ "$jqinstalled" == "" ]; then
		echo "'jq' is not installed..Proceed to install it.."
		sudo apt-get install jq
	fi

  	echo "#!/bin/sh" >  start_diehard_check.sh
  	echo "cd $DIEHARD_HOME" >> start_diehard_check.sh
  	echo "bash shift-diehard.sh check" >> start_diehard_check.sh
  	sudo chmod a+x start_diehard_check.sh
  	echo "Installation completed, now you can execute: shift-diehard.sh start"
  	echo
  	echo "To check and create snapshots every hour execute: sudo crontab -e    ..and add the following line:"
  	echo "0 * * * * /bin/su $USER -c \"cd $(pwd); bash -c $(pwd)/start_diehard_check.sh'; exec bash'\""
    echo

	CONF_FILE=diehard_config.json
	echo "{" > $CONF_FILE
	echo "	\"shift_path\" : \"$SHIFT_PATH\"," >> $CONF_FILE
	echo "	\"delegate_name\" : \"$DELEGATE_NAME\"," >> $CONF_FILE
	echo "	\"passphrase\" : \"$SECRET\"," >> $CONF_FILE
	echo "	\"delegate_address\" : \"$DELEGATE_ADDRESS\"," >> $CONF_FILE
	echo "	\"backup_ip\" : \"$BACKUP_IP\"," >> $CONF_FILE
	echo "	\"backup_port\" : \"$BACKUP_PORT\"" >> $CONF_FILE
	echo "}" >> $CONF_FILE
  fi
}

					
local_check(){
  LOCAL_HEIGHT="0"
  STATUS=$(curl -sI -k --max-time 3 --connect-timeout 3 "$HTTP://127.0.0.1:$LOCAL_PORT/api/peers" | grep "HTTP" | cut -f2 -d" ")
  if [[ "$STATUS" =~ ^[0-9]+$ ]]; then
    if [ "$STATUS" -eq "200" ]; then
        LOCAL_HEIGHT=$(curl -s -k $HTTP://127.0.0.1:$LOCAL_PORT/api/loader/status/sync | jq '.height')
        SYNC=$(curl -s -k $HTTP://127.0.0.1:$LOCAL_PORT/api/loader/status/sync | jq '.syncing')
    fi
  else
    NOW=$(date +"%d-%m-%Y - %T")
    echo "[$NOW][ERR] - ERROR : Your localhost is not responding" | tee -a $LOG
    LOCAL_HEIGHT="0"
  fi
}

					
create_snapshot() {
  #Rotate snapshots
  if [ -f "snapshot/shift_db_snapshot.tar" ]; then
     if [ -f "snapshot/shift_db_snapshot_1.tar" ]; then
        mv snapshot/shift_db_snapshot_1.tar snapshot/shift_db_snapshot_2.tar
        mv snapshot/shift_db_snapshot.tar snapshot/shift_db_snapshot_1.tar
     else
        mv snapshot/shift_db_snapshot.tar snapshot/shift_db_snapshot_1.tar
     fi
  fi
  NOW=$(date +"%d-%m-%Y - %T")
  echo "[$NOW][SNAPSHOT][INF] - Creating snapshot.." | tee -a $LOG
  rm -f 'snapshot/shift_db_snapshot.tar'
  export PGPASSWORD=$DB_PASS
  sudo su postgres -c "pg_dump -Ft $DB_NAME > 'snapshot/shift_db_snapshot.tar'" | tee -a $LOG
  #pg_dump -U $DB_USER -h localhost -p 5432 -Ft $DB_NAME > 'snapshot/shift_db_snapshot.tar' | tee -a $LOG
  NOW=$(date +"%d-%m-%Y - %T")
  if [ $? != 0 ]; then
    echo "[$NOW][SNAPSHOT][ERR] -- X Failed to create snapshot." | tee -a $LOG
    cp snapshot/shift_db_snapshot_1.tar snapshot/shift_db_snapshot.tar
  else
    dbSize=`psql -d $DB_NAME -U $DB_USER -h localhost -p 5432 -t -c "select pg_size_pretty(pg_database_size('$DB_NAME'));"`
    echo "[$NOW][SNAPSHOT][INF] -- New snapshot created successfully at block $LOCAL_HEIGHT ($dbSize)." | tee -a $LOG
  fi
}

					
restore_snapshot(){
  echo "[$NOW][REBUILD][ERR] - forever stop app.js " | tee -a $LOG
  forever stop app.js &> /dev/null
  cd $DIEHARD_HOME

  NOW=$(date +"%d-%m-%Y - %T")
  echo "[$NOW][SNAPSHOT][ERR] - Restoring snapshot" | tee -a $LOG
  if [ "$RESTORE_ATTEMPT" -eq "0" ]; then
    SNAPSHOT_FILE="snapshot/shift_db_snapshot.tar"
  else
    SNAPSHOT_FILE="snapshot/shift_db_snapshot_$RESTORE_ATTEMPT.tar"
  fi

  if [ -z "$SNAPSHOT_FILE" ]; then
    echo "[$NOW][SNAPSHOT][ERR] - X No snapshot to restore, please consider create it first" | tee -a $LOG
  else
    echo "[$NOW][SNAPSHOT][ERR] - Snapshot to restore = $SNAPSHOT_FILE" | tee -a $LOG
    #snapshot restoring..
    export PGPASSWORD=$DB_PASS
    pg_restore -d $DB_NAME "$SNAPSHOT_FILE" -U $DB_USER -h localhost -c -n public | tee -a $LOG
    NOW=$(date +"%d-%m-%Y - %T")
    if [ $? != 0 ]; then
        echo "[$NOW][SNAPSHOT][ERR] -- X Failed to restore snapshot" | tee -a $LOG
    else
        echo "[$NOW][SNAPSHOT][ERR] -- Snapshot restored successfully" | tee -a $LOG
    fi
  fi

  cd $SHIFT
  NOW=$(date +"%d-%m-%Y - %T")
  echo "[$NOW][REBUILD][ERR] - forver start app.js " | tee -a $LOG
  forever start app.js &> /dev/null
  sleep 3
}

					
localhost_check(){
  l_count="0"
   while true; do
           STATUS=$(curl -sI -k --max-time 3 --connect-timeout 3 "$HTTP://127.0.0.1:$LOCAL_PORT/api/peers" | grep "HTTP" | cut -f2 -d" ")
           if [[ "$STATUS" =~ ^[0-9]+$ ]]; then
             if [ "$STATUS" -eq "200" ]; then
                break
             fi
           else
                backup_forging
                NOW=$(date +"%d-%m-%Y - %T")
                echo "[$NOW][ERR] - Your localhost is not responding.." | tee -a $LOG
                if [ "$l_count" -gt "1" ]; then
                   #If localhost not respond in 20 seconds do reload
                   start_reload
                    l_count="0"
                   sleep 10
                else
                   echo "[$NOW][ERR] - Waiting..$l_count" | tee -a $LOG
                   sleep 10
                   ((l_count+=1))
                fi
           fi
   done
}

					
top_height(){
   TOP_HEIGHT="0"
   STATUS=$(curl -sI -k --max-time 3 --connect-timeout 3 "$HTTP://127.0.0.1:$LOCAL_PORT/api/peers" | grep "HTTP" | cut -f2 -d" ")
   if [[ "$STATUS" =~ ^[0-9]+$ ]]; then
      if [ "$STATUS" -eq "200" ]; then
        TOP_HEIGHT=$(curl -s -k $HTTP://127.0.0.1:$LOCAL_PORT/api/peers | jq '.peers[].height' | sort -nu | tail -n1)
      fi
   fi

   if [ "$TOP_HEIGHT" == "null" ]; then
      TOP_HEIGHT=$(curl -s -k https://wallet.shiftnrg.org/api/loader/status/sync | jq '.height')
   fi

   if ! [[ "$TOP_HEIGHT" =~ ^[0-9]+$ ]]; then
      NOW=$(date +"%d-%m-%Y - %T")
      echo "[$NOW][ERR] - Can't get top height from localhost, are off?" | tee -a $LOG
      TOP_HEIGHT="0"
   fi
}

                    
get_remote_height(){
    if [ "$BACKUP_HTTP" != "0" ]; then
        REMOTE_HEIGHT=$(curl -s -k --max-time 3 --connect-timeout 3 $BACKUP_HTTP://$BACKUP_IP:$BACKUP_PORT/api/loader/status/sync | jq '.height')
        if [ -z "$REMOTE_HEIGHT" ]; then
                sleep 1
                REMOTE_HEIGHT=$(curl -s -k $BACKUP_HTTP://$BACKUP_IP:$BACKUP_PORT/api/loader/status/sync | jq '.height')
                if [ -z "$REMOTE_HEIGHT" ]; then
                        echo "Remote server not responding to get remote_height $REMOTE_IP" | tee -a $LOG
                        REMOTE_HEIGHT="0"
                fi
        fi
    fi
}
					
get_local_height(){
        LOCAL_HEIGHT=$(curl -s -k --max-time 3 --connect-timeout 3 $HTTP://127.0.0.1:$LOCAL_PORT/api/loader/status/sync | jq '.height')
        if [ -z "$LOCAL_HEIGHT" ]; then
           sleep 1
           LOCAL_HEIGHT=$(curl -s -k $HTTP://127.0.0.1:$LOCAL_PORT/api/loader/status/sync | jq '.height')
                if [ -z "$LOCAL_HEIGHT" ]; then
                        NOW=$(date +"%d-%m-%Y - %T")
                        echo "[$NOW][ERR] - Localhost is not responding to get local_height" | tee -a $LOG
                        LOCAL_HEIGHT="0"
                fi
        fi
   if ! [[ "$LOCAL_HEIGHT" =~ ^[0-9]+$ ]]; then
      NOW=$(date +"%d-%m-%Y - %T")
      echo "[$NOW][ERR] - Can't get local height from localhost, are off?" | tee -a $LOG
      LOCAL_HEIGHT="0"
   fi
}

					
backup_forging(){
  if [ "$DELEGATE_ADDRESS" != "" ]; then
    STATUS=$(curl -sI -k --max-time 3 --connect-timeout 3 "$HTTP://127.0.0.1:$LOCAL_PORT/api/peers" | grep "HTTP" | cut -f2 -d" ")
    if [[ "$STATUS" =~ ^[0-9]+$ ]]; then
     if [ "$STATUS" -eq "200" ]; then  #If localhost is responding
        RESPONSE=$(curl -s -k $LOCAL_FORGING_STATUS | jq '.enabled') #true or false
        if [ "$RESPONSE" = "true" ]; then #If remote is enable, proceed to disable
            #Disable local
            NOW=$(date +"%d-%m-%Y - %T")
            echo -n "[$NOW][INF] - Disable local forging: " | tee -a $LOG
            curl -s -k -H "Content-Type: application/json" -X POST -d "{\"secret\":\"$SECRET\"}" $URL_LOCAL_DISABLE | tee -a $LOG
            echo " " | tee -a $LOG
            RESPONSE=$(curl -s -k $LOCAL_FORGING_STATUS | jq '.enabled') #true or false
            if [ "$RESPONSE" = "false" ]; then #It should not be forging in local
                echo "[$NOW][INF] - Local forging disabled successfully" | tee -a $LOG
            fi
        fi
     fi
    fi
  if [ "$BACKUP_HTTP" != "0" ]; then
    STATUS=$(curl -sI -k --max-time 3 --connect-timeout 3 "$BACKUP_HTTP://$BACKUP_IP:$BACKUP_PORT/api/peers" | grep "HTTP" | cut -f2 -d" ")
        RESPONSE=$(curl -s -k $BACKUP_FORGING_STATUS | jq '.enabled') #true or false
        if [ "$RESPONSE" = "false" ]; then #If remote is disabled, proceed to enable
            NOW=$(date +"%d-%m-%Y - %T")
            echo -n "[$NOW][INF] - Enable backup forging: " | tee -a $LOG
            curl -s -k -H "Content-Type: application/json" -X POST -d "{\"secret\":\"$SECRET\"}" $URL_BACKUP_ENABLE | tee -a $LOG
            RESPONSE=$(curl -s -k $BACKUP_FORGING_STATUS | jq '.enabled') #true or false
            echo " " | tee -a $LOG
            if [ "$RESPONSE" = "true" ]; then #Remote forging = true
                echo "[$NOW][INF] - Backup forging enabled successfully." | tee -a $LOG
            fi
        fi
  fi
    forging="backup"
  else
    forging="main"
  fi
}

					
local_forging(){
  if [ "$DELEGATE_ADDRESS" != "" ]; then
  if [ "$BACKUP_HTTP" != "0" ]; then
    STATUS=$(curl -sI -k --max-time 3 --connect-timeout 3 "$BACKUP_HTTP://$BACKUP_IP:$BACKUP_PORT/api/peers" | grep "HTTP" | cut -f2 -d" ")
        RESPONSE=$(curl -s -k $BACKUP_FORGING_STATUS | jq '.enabled') #true or false
        if [ "$RESPONSE" = "true" ]; then #If remote is disabled, proceed to enable
            NOW=$(date +"%d-%m-%Y - %T")
            echo -n "[$NOW][INF] - Disable backup forging: " | tee -a $LOG
            curl -s -k -H "Content-Type: application/json" -X POST -d "{\"secret\":\"$SECRET\"}" $URL_BACKUP_DISABLE | tee -a $LOG
            RESPONSE=$(curl -s -k $BACKUP_FORGING_STATUS | jq '.enabled') #true or false
            echo " " | tee -a $LOG
            if [ "$RESPONSE" = "false" ]; then #Remote forging = true
                echo "[$NOW][INF] - Backup forging disabled successfully." | tee -a $LOG
            fi
        fi
  fi

    STATUS=$(curl -sI -k --max-time 3 --connect-timeout 3 "$HTTP://127.0.0.1:$LOCAL_PORT/api/peers" | grep "HTTP" | cut -f2 -d" ")
    if [[ "$STATUS" =~ ^[0-9]+$ ]]; then
     if [ "$STATUS" -eq "200" ]; then  #If localhost is responding
        RESPONSE=$(curl -s -k $LOCAL_FORGING_STATUS | jq '.enabled') #true or false
        if [ "$RESPONSE" = "false" ]; then #If remote is enable, proceed to disable
            #Disable local
            NOW=$(date +"%d-%m-%Y - %T")
            echo -n "[$NOW][INF] - Enable local forging forging: " | tee -a $LOG
            curl -s -k -H "Content-Type: application/json" -X POST -d "{\"secret\":\"$SECRET\"}" $URL_LOCAL_ENABLE | tee -a $LOG
            RESPONSE=$(curl -s -k $LOCAL_FORGING_STATUS | jq '.enabled') #true or false
            echo " " | tee -a $LOG
            if [ "$RESPONSE" = "true" ]; then #It should not be forging in local
                echo "[$NOW][INF] - Local forging enabled successfully" | tee -a $LOG
            fi
        fi
     fi
    fi
    forging="local"
  else
    forging="main"
  fi
}

					
sync_status(){
    sync_counter="0"
    while true; do
        check1=`curl -k -s "$HTTP://127.0.0.1:$LOCAL_PORT/api/loader/status/sync"| jq '.height'`
        sleep 7
        if ! [[ "$check1" =~ ^[0-9]+$ ]]; then
            check1="0"
        fi
        top_height
        check_top=$(( $TOP_HEIGHT - 3 ))
        NOW=$(date +"%d-%m-%Y - %T")
        if [ "$check1" -lt "$check_top" ]; then
           pending=$(( $check_top - $check1 ))
           echo "[$NOW][SYNC][ERR] - $check1 ---> $TOP_HEIGHT still syncing... pending $pending" | tee -a $LOG
        else
           echo "[$NOW][SYNC][ERR] - $check1 - TOP HEIGHT $TOP_HEIGHT" | tee -a $LOG
           echo "[$NOW][SYNC][ERR] - Sync process finish.." | tee -a $LOG
           RESTORE_ATTEMPT="0"
           break
        fi
        ((sync_counter+=1))
        if [ "$sync_counter" -gt "20" ]; then
            ((RESTORE_ATTEMPT+=1))
            if [ "$RESTORE_ATTEMPT" -gt "2" ]; then
                RESTORE_ATTEMPT="2"
                echo "[$NOW][SYNC][ERR] - You have problems syncing, trying to sync from attempt 2 again..." | tee -a $LOG
            else
                echo "[$NOW][SYNC][ERR] - You have problems syncing, trying to sync from attempt $RESTORE_ATTEMPT again..." | tee -a $LOG
                break
            fi
        fi
    done
}

					
get_consensus(){
    LOCAL_CONSENSUS="0"
    LOCAL_CONSENSUS=$(curl -s -k $HTTP://127.0.0.1:$LOCAL_PORT/api/loader/status/sync | jq '.consensus')
    if [ "$LOCAL_CONSENSUS" == "null" ]; then
        LOCAL_CONSENSUS="100"
    else
        LOCAL_CONSENSUS=$(printf %.0f $LOCAL_CONSENSUS)
        if ! [[ "$LOCAL_CONSENSUS" =~ ^[0-9]+$ ]]; then
            LOCAL_CONSENSUS="100"
        fi
    fi
    
    REMOTE_CONSENSUS="0"
    if [ "$BACKUP_HTTP" != "0" ]; then
        REMOTE_CONSENSUS=$(curl -s -k $BACKUP_HTTP://$BACKUP_IP:$BACKUP_PORT/api/loader/status/sync | jq '.consensus')
        if [ "$REMOTE_CONSENSUS" == "null" ]; then
            REMOTE_CONSENSUS="0"
        else
            REMOTE_CONSENSUS=$(printf %.0f $REMOTE_CONSENSUS)
            if ! [[ "$REMOTE_CONSENSUS" =~ ^[0-9]+$ ]]; then
                REMOTE_CONSENSUS="0"
            fi
        fi
    fi
}

					
get_nextturn(){
  if [ "$DELEGATE_ADDRESS" != "" ]; then
    RESPONSE=$(curl -s -k $HTTP://127.0.0.1:$LOCAL_PORT/api/delegates/getNextForgers?limit=101 | jq '.delegates')
    i="0"
    while [ "$i" -lt "101" ]; do
        v1=$(echo $RESPONSE | jq '.['$i']')
        PK="${v1//\"/}"
        if [ "$PK" == "$PUBLICKEY" ]; then
            NEXTTURN=$(( $i * 27 ))
            break
        fi
        ((i+=1))
    done
    if ! [[ "$NEXTTURN" =~ ^[0-9]+$ ]]; then
        NEXTTURN="200"
    fi
    if [ "$NEXTTURN" -le "27" ]; then
        SLEEP_TIME="0";
    else
        SLEEP_TIME="20"
    fi
  else
    NEXTTURN="1000"
  fi
}

                    
check_forged_blocks(){
    if [ "$NEXTTURN" -le "10" ] && [ "$FORGE_FLAG" -eq "0" ]; then
        FORGE_FLAG="1"
        FORGE_COUNTER="0"
    fi
    
    if [ "$FORGE_FLAG" -eq "1" ]; then
        NOW=$(date +"%d-%m-%Y - %T")
        have_forged=`tail logs/shift.log -n 100 | grep "Forged"`
        if [ -n "$have_forged" ]; then
            echo "[$NOW][FORGED] - $have_forged" | tee -a $LOG
            FORGE_FLAG="0"
        fi
        if [ "$NEXTTURN" -gt "100" ]; then
            ((FORGE_COUNTER+=1))
            if [ "$FORGE_COUNTER" -eq "3" ]; then
                echo "[$NOW][FORGED][ERR] - It seems that you lost the block" | tee -a $LOG
                FORGE_FLAG="0"
            fi
        fi
    fi
}

					
found_fork(){
    FORK=$1
    NOW=$(date +"%d-%m-%Y - %T")
    echo "[$NOW][FORK][ERR] - Found fork: $FORK -- turn $NEXTTURN s" | tee -a $LOG
    FORK_JSON=$(echo $FORK | awk -F "Fork - " '{ print $2 }')
    v1=$(echo $FORK_JSON | jq '.delegate')
    PK="${v1//\"/}"
    v1=$(curl -s -k -X GET $HTTP://127.0.0.1:$LOCAL_PORT/api/delegates/get?publicKey=$PK | jq '.delegate.username')
    FORK_DELEGATE="${v1//\"/}"
    FORK_CAUSE=$(echo $FORK_JSON | jq '.cause')

    echo "$FORK" | grep "\"cause\":2" | tee -a $LOG
	if [ $? = 0 ]; then
    	echo "[$NOW][FORK][ERR] - Delegate $FORK_DELEGATE -- Cause = $FORK_CAUSE -- Restarting node main." | tee -a $LOG
        start_reload
    else
        echo "[$NOW][FORK][ERR] - Delegate $FORK_DELEGATE -- Cause = $FORK_CAUSE -- Rebuilding node main." | tee -a $LOG
        start_rebuild
    fi
}

					
start_reload(){
  backup_forging
  NOW=$(date +"%d-%m-%Y - %T")
  echo "[$NOW][RELOAD][ERR] - Starting reload.." | tee -a $LOG
  echo "[$NOW][RELOAD][ERR] - forever stop app.js " | tee -a $LOG
  forever stop app.js &> /dev/null
  NOW=$(date +"%d-%m-%Y - %T")
  echo "[$NOW][RELOAD][ERR] - forver start app.js " | tee -a $LOG
  forever start app.js &> /dev/null
  sleep 3
  localhost_check
  NOW=$(date +"%d-%m-%Y - %T")
  echo "[$NOW][RELOAD][ERR] - Reload finished." | tee -a $LOG
}

					
start_rebuild(){
  NOW=$(date +"%d-%m-%Y - %T")
  echo "[$NOW][REBUILD][ERR] - Starting rebuild" | tee -a $LOG
  echo "[$NOW][REBUILD][ERR] - Rebuilding with heights: Highest: $TOP_HEIGHT -- Local: $LOCAL_HEIGHT ($LOCAL_CONSENSUS %) $BAD_CONSENSUS" | tee -a $LOG
  backup_forging
  restore_snapshot
  localhost_check
  backup_forging
  NOW=$(date +"%d-%m-%Y - %T")
  echo "[$NOW][REBUILD][ERR] - Rebuild finish.. start syncing.." | tee -a $LOG
  sync_status
  if [ "$RESTORE_ATTEMPT" -ne "0" ]; then
    restore_snapshot
    localhost_check
    backup_forging
    NOW=$(date +"%d-%m-%Y - %T")
    echo "[$NOW][REBUILD][ERR] - Rebuild finish.. start syncing.." | tee -a $LOG
  fi
  if [ "$RESTORE_ATTEMPT" -ne "0" ]; then
    restore_snapshot
    localhost_check
    backup_forging
    NOW=$(date +"%d-%m-%Y - %T")
    echo "[$NOW][REBUILD][ERR] - Rebuild finish.. start syncing.." | tee -a $LOG
    sync_status
  fi
  if [ "$RESTORE_ATTEMPT" -ne "0" ]; then
    restore_snapshot
    localhost_check
    backup_forging
    NOW=$(date +"%d-%m-%Y - %T")
    echo "[$NOW][REBUILD][ERR] - Something is wrong with your syncing" | tee -a $LOG
    sync_status
  fi
}

					
rotate_logs(){
    max_size="10485760" #10 MB
    checklog=logs/diehard.log
    size=$(du -b $checklog | tr -s '\t' ' ' | cut -d' ' -f1)
    if [ "$size" -ge "$max_size" ]; then
        NOW=$(date +"%d-%m-%Y - %T")
        echo -n "[$NOW][INF] - Log $checklog need rotation.." | tee -a $LOG
        gzip -c $checklog > "$checklog.$NOW.gz"
        rm $checklog
        echo "done" | tee -a $LOG
    fi
    checklog=logs/diehard_check.log
    size=$(du -b $checklog | tr -s '\t' ' ' | cut -d' ' -f1)
    if [ "$size" -ge "$max_size" ]; then
        NOW=$(date +"%d-%m-%Y - %T")
        echo -n "[$NOW][INF] - Log $checklog need rotation.." | tee -a $LOG
        gzip -c $checklog > "$checklog.$NOW.gz"
        rm $checklog
        echo "done" | tee -a $LOG
    fi
}

                                        
start_shift(){
  NOW=$(date +"%d-%m-%Y - %T")
  forever=$(forever list | grep "No forever processes running")
  cd $SHIFT
  if [ "$forever" != "" ]; then
    echo "[$NOW][INF] - Starting Shift.." | tee -a $LOG
    NOW=$(date +"%d-%m-%Y - %T")
    echo "[$NOW][INF] - Starting Shift forever start app.js " | tee -a $LOG
    forever start app.js &> /dev/null
    sleep 3
    localhost_check
    NOW=$(date +"%d-%m-%Y - %T")
    echo "[$NOW][INF] - Your Shift instance has started." | tee -a $LOG
  fi
}

					
initialize(){
  NOW=$(date +"%d-%m-%Y - %T")
  echo " " | tee -a $LOG
  echo "[$NOW] - Initializing.." | tee -a $LOG
  config=diehard_config.json
  if ! [ -f $config ]; then
    echo "No diehard installation detected, please run: bash shift_diehard.sh install"
    exit 0
  fi
  v1=$(cat $config | jq '.shift_path')
  SHIFT="${v1//\"/}"
  SHIFT_CONFIG=$SHIFT'config.json'
  echo -n "[$NOW][INF] - Load Shift configuration.." | tee -a $LOG
  if [ -f $SHIFT_CONFIG ]; then
    HTTP="http"
    HTTPS=$(cat $SHIFT_CONFIG | jq '.ssl.enabled')
    if [ $HTTPS == true ]; then
        HTTP="https"
        LOCAL_PORT=$(cat $SHIFT_CONFIG | jq '.ssl.options.port')
    else
        LOCAL_PORT=$(cat $SHIFT_CONFIG | jq '.port')
    fi
    v1=$(cat $SHIFT_CONFIG | jq '.db.database')
    DB_NAME="${v1//\"/}"
    v1=$(cat $SHIFT_CONFIG | jq '.db.user')
    DB_USER="${v1//\"/}"
    v1=$(cat $SHIFT_CONFIG | jq '.db.password')
    DB_PASS="${v1//\"/}"
  else
    echo " " | tee -a $LOG
    echo "[$NOW][ERR] - Error: No shift installation detected in $SHIFT" | tee -a $LOG
    echo "[$NOW][ERR] - Exiting.." | tee -a $LOG
    exit 0
  fi
  echo "done." | tee -a $LOG

  v1=$(cat $config | jq '.delegate_name')
  DELEGATE_NAME="${v1//\"/}"
  v1=$(cat $config | jq '.passphrase')
  SECRET="${v1//\"/}"
  v1=$(cat $config | jq '.delegate_address')
  DELEGATE_ADDRESS="${v1//\"/}"
  v1=$(cat $config | jq '.backup_ip')
  BACKUP_IP="${v1//\"/}"
  v1=$(cat $config | jq '.backup_port')
  BACKUP_PORT="${v1//\"/}"
  start_shift
}

					
force_restore(){
  LOG=$DIEHARD_HOME/logs/force_restore.log
  initialize
  NOW=$(date +"%d-%m-%Y - %T")
  echo "[$NOW][INF] - Starting restore by force" | tee -a $LOG
  restore_snapshot
  NOW=$(date +"%d-%m-%Y - %T")
  echo "[$NOW][INF] - Restore by force finish" | tee -a $LOG
}

					
shift_diehard_check(){
  LOG=$DIEHARD_HOME/logs/diehard_check.log
  initialize
  NOW=$(date +"%d-%m-%Y - %T")
  echo "[$NOW][INF] - Starting checkup" | tee -a $LOG
  forever=$(forever list | grep "No forever processes running")
  if [ "$forever" != "" ]; then
    echo "[$NOW][ERR] - Shift is not running with forever.. checking if localhost is listening" | tee -a $LOG
    local_check
    if [ "$LOCAL_HEIGHT" -eq "0" ]; then
        echo "[$NOW][ERR] - Localhost is not listening, proceed to start app.js" | tee -a $LOG
        cd $SHIFT
        echo -n "[$NOW][ERR] - forever start app.js: " | tee -a $LOG
        forever start app.js | tee -a $LOG
        local_check
        NOW=$(date +"%d-%m-%Y - %T")
        if [ "$LOCAL_HEIGHT" -eq "0" ]; then
            echo "[$NOW][ERR] - Could not start app.js" | tee -a $LOG
        else
            echo "[$NOW][INF] - Shift started successfully" | tee -a $LOG
        fi
    else
        echo "[$NOW][INF] - Shift is running but not with forever, this may cause problems with shift-diehard.sh script" | tee -a $LOG
    fi
  else
    echo "[$NOW][INF] - Shift is running good" | tee -a $LOG
  fi
  local_check
  top_height
  get_consensus
  diff=$(( $TOP_HEIGHT - $LOCAL_HEIGHT ))
  NOW=$(date +"%d-%m-%Y - %T")
  cd $DIEHARD_HOME
  if [ "$diff" -lt "3" ]; then
    if [ "$LOCAL_HEIGHT" -eq "0" ]; then
        echo "[$NOW][ERR] - X Failed to create snapshot. Your localhost is not responding." | tee -a $LOG
    else
        echo "[$NOW][INF] - Top Heigh = $TOP_HEIGHT , Local Height = $LOCAL_HEIGHT. Difference = $diff , Local Consensus = $LOCAL_CONSENSUS %" | tee -a $LOG
        if [ "$SYNC" = "true" ]; then
            echo "[$NOW][INF] - Blockchain syncing, wait until the blockchain is synced.." | tee -a $LOG
            sync_status
	       SYNC="0"
        fi
        create_snapshot
    fi
  else
    echo "[$NOW][ERR] - X Failed to create snapshot. Top Heigh = $TOP_HEIGHT , Local Height = $LOCAL_HEIGHT. Difference = $diff , Local Consensus = $LOCAL_CONSENSUS %." | tee -a $LOG
  fi
  rotate_logs
}

					
backup_test(){
    NOW=$(date +"%d-%m-%Y - %T")
    echo -n "[$NOW][INF] - Load backup configuration..." | tee -a $LOG
    STATUS=$(curl -sI -k --max-time 3 --connect-timeout 3 "http://$BACKUP_IP:$BACKUP_PORT/api/peers" | grep "HTTP" | cut -f2 -d" ")
      if [[ "$STATUS" =~ ^[0-9]+$ ]]; then
        if [ "$STATUS" -eq "200" ]; then
            echo "done" | tee -a $LOG
            BACKUP_HTTP="http"
        fi
      fi
    STATUS=$(curl -sI -k --max-time 3 --connect-timeout 3 "https://$BACKUP_IP:$BACKUP_PORT/api/peers" | grep "HTTP" | cut -f2 -d" ")
      if [[ "$STATUS" =~ ^[0-9]+$ ]]; then
        if [ "$STATUS" -eq "200" ]; then
            echo "done" | tee -a $LOG
            BACKUP_HTTP="https"
        fi
      fi

      if [ "$BACKUP_HTTP" == "0" ]; then
        NOW=$(date +"%d-%m-%Y - %T")
        echo " " | tee -a $LOG
        echo "[$NOW][ERR] - Backup not responding. You configured a backup but is not responding. Please make sure your main node have access to your backup." | tee -a $LOG
        echo "[$NOW][ERR] - Exiting.." | tee -a $LOG
        exit 0
      fi

  URL_BACKUP_ENABLE="$BACKUP_HTTP://$BACKUP_IP:$BACKUP_PORT/api/delegates/forging/enable"
  URL_BACKUP_DISABLE="$BACKUP_HTTP://$BACKUP_IP:$BACKUP_PORT/api/delegates/forging/disable"
  BACKUP_FORGING_STATUS="$BACKUP_HTTP://$BACKUP_IP:$BACKUP_PORT/api/delegates/forging/status?publicKey=$PUBLICKEY"
  curl -s -k -H "Content-Type: application/json" -X POST -d "{\"secret\":\"$SECRET\"}" $URL_BACKUP_DISABLE &> /dev/null
  NOW=$(date +"%d-%m-%Y - %T")
  echo -n "[$NOW][INF] - Testing backup forging: " | tee -a $LOG
  curl -s -k -H "Content-Type: application/json" -X POST -d "{\"secret\":\"$SECRET\"}" $URL_BACKUP_ENABLE | tee -a $LOG
    RESPONSE=$(curl -s -k $BACKUP_FORGING_STATUS | jq '.enabled') #true or false
    echo " " | tee -a $LOG
    if [ "$RESPONSE" = "true" ]; then #Remote forging = true
        echo "[$NOW][INF] - Enabled backup forging successfully." | tee -a $LOG
    else
        echo "[$NOW][INF] - Could not enabled backup forging. Please check your backup configuration and try again." | tee -a $LOG
        echo "[$NOW][INF] - Exiting.." | tee -a $LOG
        exit 0.
    fi
  echo -n "[$NOW][INF] - Testing backup disable forging: " | tee -a $LOG
  curl -s -k -H "Content-Type: application/json" -X POST -d "{\"secret\":\"$SECRET\"}" $URL_BACKUP_DISABLE | tee -a $LOG
    RESPONSE=$(curl -s -k $BACKUP_FORGING_STATUS | jq '.enabled') #true or false
    echo " " | tee -a $LOG
    if [ "$RESPONSE" = "false" ]; then
        echo "[$NOW][INF] - Disable backup forging successfully." | tee -a $LOG
    else
        echo "[$NOW][INF] - Could not disable backup forging. Please check your backup configuration and try again." | tee -a $LOG
        echo "[$NOW][INF] - Exiting.." | tee -a $LOG
        exit 0.
    fi
}

					
shift_diehard_start(){
  LOG=$DIEHARD_HOME/logs/diehard.log
  initialize
  forever=$(forever list | grep "No forever processes running")
  if [ "$forever" != "" ]; then
    echo "You must have running Shift with forever, please stop your Shift instance and start it with: forever start app.js" | tee -a $LOG
    echo "After that you can run again: bash shift-diehard.sh start" | tee -a $LOG
    exit 0
  fi
  echo -n "[$NOW][INF] - Load localhost configuration.." | tee -a $LOG
  STATUS=$(curl -sI -k --max-time 3 --connect-timeout 3 "$HTTP://localhost:$LOCAL_PORT/api/peers" | grep "HTTP" | cut -f2 -d" ")
  if [[ "$STATUS" =~ ^[0-9]+$ ]]; then
    if [ "$STATUS" -eq "200" ]; then
        echo "done" | tee -a $LOG
    fi
  else
    NOW=$(date +"%d-%m-%Y - %T")
    echo " " | tee -a $LOG
    echo "[$NOW][INF] - Localhost not responding. Please make sure your Shift installation is running correctly." | tee -a $LOG
    echo "[$NOW][INF] - Exiting.." | tee -a $LOG
    exit 0
  fi

  v1=$(curl -s -k $HTTP://127.0.0.1:$LOCAL_PORT/api/accounts/getPublicKey?address=$DELEGATE_ADDRESS | jq '.publicKey')
  PUBLICKEY="${v1//\"/}"
  URL_LOCAL_ENABLE="$HTTP://127.0.0.1:$LOCAL_PORT/api/delegates/forging/enable"
  URL_LOCAL_DISABLE="$HTTP://127.0.0.1:$LOCAL_PORT/api/delegates/forging/disable"
  LOCAL_FORGING_STATUS="$HTTP://127.0.0.1:$LOCAL_PORT/api/delegates/forging/status?publicKey=$PUBLICKEY"  
  BACKUP_HTTP="0"
  if [ "$BACKUP_IP" != "" ]; then
    backup_test
  fi

  NOW=$(date +"%d-%m-%Y - %T")
  echo "[$NOW][INF] - Starting shift-diehard." | tee -a $LOG
  echo "[$NOW][INF] - Delegate name : $DELEGATE_NAME" | tee -a $LOG
  echo "[$NOW][INF] - Delegate address : $DELEGATE_ADDRESS" | tee -a $LOG
  echo "[$NOW][INF] - Delegate publicKey : $PUBLICKEY" | tee -a $LOG
  
  ****ESPECIFICAR CONEXIONES HTTPS Y SERVIDORES
  
  echo -n "[$NOW][INF] - Initial forging local disable: " | tee -a $LOG
  curl -s -k -H "Content-Type: application/json" -X POST -d "{\"secret\":\"$SECRET\"}" $URL_LOCAL_DISABLE | tee -a $LOG
  echo " " | tee -a $LOG
  echo -n "[$NOW][INF] - Initial forging backup disable: " | tee -a $LOG
  if [ "$BACKUP_HTTP" != "0" ]; then
    curl -s -k -H "Content-Type: application/json" -X POST -d "{\"secret\":\"$SECRET\"}" $URL_BACKUP_DISABLE | tee -a $LOG
  else
    echo "no backup selected."
  fi
  echo " " | tee -a $LOG

  BAD_CONSENSUS="0"
  PRV="0"
  SLEEP_TIME="20"
  FORGE_FLAG="0"
  RESTORE_ATTEMPT="0"
  cd $SHIFT
  while true; do
    localhost_check
    top_height
    get_local_height
    get_remote_height
    get_consensus
    get_nextturn
    check_forged_blocks

    is_forked=`tail logs/shift.log -n 40 | grep "Fork"`
    if [ -n "$is_forked" ]; then
        found_fork "$is_forked"
    fi

    if [ "$LOCAL_CONSENSUS" -lt "51" ]; then
        ((BAD_CONSENSUS+=1))
        backup_forging
    else
        BAD_CONSENSUS="0"
        local_forging
    fi

    diff=$(( $TOP_HEIGHT - $LOCAL_HEIGHT ))
    if [ "$diff" -gt "3" ] && [ "$NEXTTURN" -gt "50" ]; then
        NOW=$(date +"%d-%m-%Y - %T")
        echo "[$NOW][ERR] - Top height $TOP_HEIGHT - Local height $LOCAL_HEIGHT = difference $diff -- Local Consensus $LOCAL_CONSENSUS.. reload -- turn $NEXTTURN s" | tee -a $LOG
        start_reload
        get_local_height
        diff=$(( $TOP_HEIGHT - $LOCAL_HEIGHT ))
        ## Rebuild if still out of sync after reload
        if [ "$diff" -gt "4" ]; then
            start_rebuild
        fi
    fi

    if [ "$BAD_CONSENSUS" -eq "40" ] || [ "$BAD_CONSENSUS" -eq "24" ] || [ "$BAD_CONSENSUS" -eq "16" ] || [ "$BAD_CONSENSUS" -eq "8" ]; then
        start_reload
    fi
    
    get_consensus
    if ( [ "$NEXTTURN" -gt "20" ] && [ "$NEXTTURN" -lt "100" ] ) && [ "$LOCAL_CONSENSUS" -lt "51" ]; then
        start_reload
    fi

    if [ "$BAD_CONSENSUS" -gt "50" ] && [ "$NEXTTURN" -gt "100" ]; then
        start_rebuild
    fi

    NOW=$(date +"%d-%m-%Y - %T")
    if [ "$NEXTTURN" -gt "27" ]; then
        if [ "$PRV" -eq "0" ]; then
            echo " " | tee -a $LOG
            echo "Start normal surveillance" | tee -a $LOG
        fi

        echo "[$NOW][INF] - Forging $forging | TH = $TOP_HEIGHT | LH = $LOCAL_HEIGHT | LC = $LOCAL_CONSENSUS % | RH $REMOTE_HEIGHT | RC $REMOTE_CONSENSUS | NT = $NEXTTURN s " | tee -a $LOG
        PRV=$NEXTTURN
    else
        if [ "$PRV" -eq "$NEXTTURN" ]; then
            echo -n "." | tee -a $LOG
        else
            echo " " | tee -a $LOG
            if [ "$NEXTTURN" -ne "0" ]; then echo "Start sharper surveillance.." | tee -a $LOG; fi
            echo "[$NOW][INF] - Forging $forging | TH = $TOP_HEIGHT | LH = $LOCAL_HEIGHT | LC = $LOCAL_CONSENSUS % | RH $REMOTE_HEIGHT | RC $REMOTE_CONSENSUS | NT = $NEXTTURN s" | tee -a $LOG
            PRV=$NEXTTURN
        fi
    fi
    sleep $SLEEP_TIME
  done
}

################################################################################
										
case $1 in
"install")
  install_diehard
  ;;
"start")
  shift_diehard_start
  ;;
"check")
  shift_diehard_check
  ;;
"force_restore")
  force_restore
  ;;
"help")
  echo "Available commands are: "
  echo "  install  	- Installs the necessary requirements"
  echo "  start    	- Start diehard script"
  echo "  check    	- Does a general check and generates a snapshot"
  echo "  force_restore - Restores by force, this is for when your Shift instance is running but it does not recognize that it is in the wrong chain."
  ;;
*)
  echo "Error: Unrecognized command."
  echo ""
  echo "Available commands are: install, start, check, force_restore, help"
  echo "Try: bash shift-snapshot.sh help"
  ;;
esac
