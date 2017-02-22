#!/bin/bash
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8

SHIFT_CONFIG=~/shift/config.json
DB_NAME="$(grep "database" $SHIFT_CONFIG | cut -f 4 -d '"')"
DB_USER="$(grep "user" $SHIFT_CONFIG | cut -f 4 -d '"')"
DB_PASS="$(grep "password" $SHIFT_CONFIG | cut -f 4 -d '"' | head -1)"
DB_HOST=localhost
DB_SCHEMA=public

start_vacuum()
{
    echo "Starting VACUUM process.."
    psql_tbls="\dt $PGSCHEMA.*"
    sed_str="s/$DB_SCHEMA\s+\|\s+(\w+)\s+\|.*/\1/p"
    export PGPASSWORD=$DB_PASS
    table_names=`psql -d $DB_NAME -U $DB_USER -h localhost -p 5432 -t -c "\dt;" | sed -nr "$sed_str"`
    tables_array=($(echo $table_names | tr '\n' ' '))
    for t in "${tables_array[@]}"
    do
        q="VACUUM ANALYZE $DB_SCHEMA.$t;"
        #echo "psql -d $DB_NAME -U $DB_USER -h $DB_HOST -c $q"
        psql -d $DB_NAME -U $DB_USER -h $DB_HOST -c "$q" &> /dev/null
    done
    echo "Process finish.."
}

start_vacuum;

