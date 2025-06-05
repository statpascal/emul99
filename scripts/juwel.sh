#!/bin/bash

cd "$(dirname "$0")"/..

WAIT_TIME=30
USE_XAS99=true

JUWEL_KEY_IN=/tmp/juwel_key_in
XB_KEY_IN=/tmp/xb_key_in
DISKSIM_DIR=juwel7

MERGE_FILE=DSK1.$1-M
TXT_FILE_HOST=$DISKSIM_DIR/$1.TXT
OBJ_FILE_HOST=$DISKSIM_DIR/$1.OBJ
XB_FILE=$1

export PATH=$PATH:/usr/local/bin

if [ "$2" == "XB" ]; then
    KEY_IN=$XB_KEY_IN
    USE_XB=true
else
    KEY_IN=$JUWEL_KEY_IN
    USE_XB=false
fi

maxspeed () {
    echo -n $'\xfd' > $KEY_IN
}
    
normspeed () {
    echo -n $'\xfc' > $KEY_IN
}

pause () {
    echo -n $'\xfb'$1 > $KEY_IN
}

returnkey () {
    for in in $(seq $1); do
        echo -n $'\x0a' > $KEY_IN
        pause $'\x05'
    done
}

waitforfile () {
    until [ -s $1 ] ; do sleep 0.1; done
    flock -w $WAIT_TIME $1 echo "Emulator finished writing " $1
}

juwel_assembler () {
    # Select Assembler and ack options - the assembler opens the output file
    # twice so we need to wait two times
    maxspeed
    returnkey 5
    normspeed
    returnkey 1
    waitforfile $OBJ_FILE_HOST
    rm $OBJ_FILE_HOST
    maxspeed
    waitforfile $OBJ_FILE_HOST
    echo "Assembler is done"
    returnkey 1
    sleep 1
    normspeed
}

xas99_assembler () {
    rm -f /tmp/tmp.obj
    ../xdt99/xas99.py -s -R $TXT_FILE_HOST -I $DISKSIM_DIR -o /tmp/tmp.obj
    ../xdt99/xdm99.py -T /tmp/tmp.obj -f DIS/FIX80 -o $OBJ_FILE_HOST
}

start_emul99 () {
    if [ $USE_XB == true ]; then
        CONFIG="bin/exbasic.cfg cpu_freq=100000000"
    else
        CONFIG=bin/juwel7.cfg
    fi
    
    found=false
    for pid in $(pidof emul99); do
        if ps -p $pid -o args | grep -q key_input=$KEY_IN; then
            echo "Found emul99 as pid" $pid
            found=true
            echo -n $'\xfe' > $KEY_IN
        fi
    done
    if [ $found == false ]; then
        echo "Starting emul99"
        rm -f $KEY_IN
        nohup bin/emul99 $CONFIG disksim_dir=$DISKSIM_DIR key_input=$KEY_IN >/dev/null &
        until [ -p $KEY_IN ] ; do sleep 0.1; done
    fi
}

handle_Juwel7 () {
    # Select Compiler
    returnkey 1
    maxspeed
    sleep 1
    normspeed

    echo $MERGE_FILE > $KEY_IN
    returnkey 1
    if [ $USE_XAS99 == true ]; then
        echo -n Y > $KEY_IN
        returnkey 3
    else
        echo -n N > $KEY_IN
        returnkey 4
    fi

    maxspeed
    waitforfile $TXT_FILE_HOST
    normspeed

    if [ $USE_XAS99 == true ]; then
        xas99_assembler
    else
        juwel_assembler
    fi
    echo "Assembler finished"

    # Select Loader and execute
    maxspeed
    returnkey 6
    normspeed
    echo "Executing compiled program"
}

handle_XB () {
    echo RUN \"DSK0.$XB_FILE\" > $KEY_IN
}

rm -f $TXT_FILE_HOST $OBJ_FILE_HOST
start_emul99
maxspeed
sleep 1
echo -n 22 > $KEY_IN
sleep 2
normspeed

if [ $USE_XB == true ]; then
    handle_XB
else
    handle_Juwel7
fi

