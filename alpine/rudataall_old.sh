#! /bin/bash
#pmIp="192.168.10.102"
# Capture the resource utilization profile of the Virtural Machine, the 
# docker container, as well as the processes statistics inside the container. 

# The first time this is run current cpu, disk, and network storage is snapshot
# The second time this is run the differences are calculated in order to determine 
# the CPU time, Sectors read/written, and Network bytes rcv'd/transmitted 

# flags -v, -c, and -p can be used to ommit vm, container, and/or process-level metric respectively

# Notes for VM level statistics:
# CPU time is in hundreths of a second (centisecond:cs)
# Sectors read is number of sectors read, where a sector is typically 512 bytes (col 2) assumes /dev/sda1
# Sectors written (col 3) assumes /dev/sda1
# network Bytes recv'd assumes eth0 (col ?)
# network Bytes written assumes eth0 (col ?)
# col 6 cpu time for processes executing in user mode
# col 7 cpu time for processes executing in kernel mode
# col 8 cpu idle time
# col 9 cpu time waiting for I/O to complete
# col 10 cpu time servicing interrupts
# col 11 cpu time servicing soft interrupts
# col 12 number of context switches
# col 13 number of disk reads completed succesfully
# col 14 number of disk reads merged together (adjacent and merged for efficiency) 
# col 15 time in ms spent reading
# col 16 number of disk writes completed succesfully
# col 17 number of disk writes merged together (adjacent and merged for efficiency)
# col 18 time in ms spent writing

# Notes for container level statistics:
# TBD...

# Notes for process level statistics:
# TBD...
 
VM=false
CONTAINER=false
PROCESS=false

#get the flags and omit levels as requested
if [ $# -eq 0 ]
then
  VM=true;CONTAINER=true;PROCESS=true
else
  while [ -n "$1" ]
  do
    case "$1" in
      -v) VM=true;;
      -c) CONTAINER=true;;
      -p) PROCESS=true;;
    esac
    shift
  done
fi    

outfile=rudata_all.json
echo "{" > $outfile
epochtime=$(date +%s)

# Find the number of processes inside the container
IFS=$'\n'
PPS=(`cat /sys/fs/cgroup/pids/tasks`)
unset IFS
length=${#PPS[@]}
PIDS=$((length-2)) 

## VM level metrics

if [ $VM = true ]
then
  #echo "VM is Running!!"

  T_VM_1=$(date +%s%3N)

  # Get CPU stats
  CPU=(`cat /proc/stat | grep '^cpu '`)
  unset CPU[0]
  CPUUSR=${CPU[1]}
  T_CPUUSR=$(date +%s%3N)
  CPUNICE=${CPU[2]}
  T_CPUNICE=$(date +%s%3N)
  CPUKRN=${CPU[3]}
  T_CPUKRN=$(date +%s%3N)
  CPUIDLE=${CPU[4]}  
  T_CPUIDLE=$(date +%s%3N)
  CPUIOWAIT=${CPU[5]}
  T_CPUIOWAIT=$(date +%s%3N)
  CPUIRQ=${CPU[6]}
  T_CPUIRQ=$(date +%s%3N)
  CPUSOFTIRQ=${CPU[7]}
  T_CPUSOFTIRQ=$(date +%s%3N)
  CPUSTEAL=${CPU[8]}
  T_CPUSTEAL=$(date +%s%3N)
  CPUTOT=`expr $CPUUSR + $CPUKRN`
  T_CPUTOT=$(date +%s%3N)
  CONTEXT=(`cat /proc/stat | grep '^ctxt '`)
  unset CONTEXT[0]
  CSWITCH=${CONTEXT[1]}
  T_CSWITCH=$(date +%s%3N) 

  # Get disk stats
  COMPLETEDREADS=0
  MERGEDREADS=0
  SR=0
  READTIME=0
  COMPLETEDWRITES=0
  MERGEDWRITES=0
  SW=0
  WRITETIME=0

  IFS=$'\n'
  CPU_TYPE=(`cat /proc/cpuinfo | grep 'model name' | cut -d":" -f 2 | sed 's/^ *//'`)
  CPU_MHZ=(`cat /proc/cpuinfo | grep 'cpu MHz' | cut -d":" -f 2 | sed 's/^ *//'`)
  CPUTYPE=${CPU_TYPE[0]}
  T_CPUTYPE=$(date +%s%3N)
  CPUMHZ=${CPU_MHZ[0]}
  T_CPUMHZ=$(date +%s%3N)

DISK="$(lsblk -nd --output NAME,TYPE | grep disk)"
DISK=${DISK//disk/}
DISK=($DISK)
#DISK is now an array containing all names of our unique disk devices

unset IFS
length=${#DISK[@]}


for (( i=0 ; i < length; i++ ))
    do
      currdisk=($(cat /proc/diskstats | grep ${DISK[i]}) )
      COMPLETEDREADS=`expr ${currdisk[3]} + $COMPLETEDREADS`
      MERGEDREADS=`expr ${currdisk[4]} + $MERGEDREADS`
      SR=`expr ${currdisk[5]} + $SR`
      READTIME=`expr ${currdisk[6]} + $READTIME`
      COMPLETEDWRITES=`expr ${currdisk[7]} + $COMPLETEDWRITES`
      MERGEDWRITES=`expr ${currdisk[8]} + $MERGEDWRITES`
      SW=`expr ${currdisk[9]} + $SW`
      WRITETIME=`expr ${currdisk[10]} + $WRITETIME`
    done

  # Get network stats
  BR=0
  BT=0
  IFS=$'\n'
  NET=($(cat /proc/net/dev | grep 'eth0') )
  unset IFS
  length=${#NET[@]}
  #Parse multiple network adapters if they exist
  if [ $length > 1 ]
  then
    for (( i=0 ; i < length; i++ ))
    do
      currnet=(${NET[$i]})
      BR=`expr ${currnet[1]} + $BR`
      BT=`expr ${currnet[9]} + $BT`
    done
  else
    NET=(`cat /proc/net/dev | grep 'eth0'`)
    space=`expr substr $NET 6 1`
    # Need to determine which column to use based on spacing of 1st col
    if [ -z $space  ]
    then
      BR=${NET[1]}
      BT=${NET[9]}
    else
      BR=`expr substr $NET 6 500`
      BT=${NET[8]}
    fi
  fi
  LOADAVG=(`cat /proc/loadavg`)
  LAVG=${LOADAVG[0]}

  # Get Memory Stats
  MEMTOT=$(cat /proc/meminfo | grep 'MemTotal' | cut -d":" -f 2 | sed 's/^ *//' | cut -d" " -f 1 ) # in KB

  MEMFREE=$(cat /proc/meminfo | grep 'MemFree' | cut -d":" -f 2 | sed 's/^ *//' | cut -d" " -f 1 ) # in KB

  BUFFERS=$(cat /proc/meminfo | grep 'Buffers' | cut -d":" -f 2 | sed 's/^ *//' | cut -d" " -f 1 ) # in KB

  CACHED=$(cat /proc/meminfo | grep -w 'Cached' | cut -d":" -f 2 | sed 's/^ *//' | cut -d" " -f 1 ) # in KB


  vmid="unavailable"

  T_VM_2=$(date +%s%3N)
  let T_VM=$T_VM_2-$T_VM_1

	
 #experimental pagefault
 filedata() {
     volumes=$(cat $1 | grep -m 1 -i $2)
     tr " " "\n" <<< $volumes | tail -n1 
    
 }
 vPGFault=$(filedata "/proc/vmstat" "pgfault")
 vMajorPGFault=$(filedata "/proc/vmstat" "pgmajfault")
 #

  
  echo "  \"currentTime\": $epochtime," >> $outfile
  echo "  \"vMetricType\": \"VM level\"," >> $outfile
  echo "  \"vTime\": $T_VM," >> $outfile 
  ## print VM level data 
  echo "  \"vCpuTime\": $CPUTOT," >> $outfile
  echo "  \"tvCpuTime\": $T_CPUTOT," >> $outfile
  echo "  \"vDiskSectorReads\": $SR," >> $outfile

  echo "  \"vDiskSectorWrites\": $SW," >> $outfile
  echo "  \"vNetworkBytesRecvd\": $BR," >> $outfile
  echo "  \"vNetworkBytesSent\": $BT," >> $outfile
  echo "  \"vPgFault\": $vPGFault," >> $outfile
  echo "  \"vMajorPageFault\": $vMajorPGFault," >> $outfile
  echo "  \"vCpuTimeUserMode\": $CPUUSR," >> $outfile
  echo "  \"tvCpuTimeUserMode\": $T_CPUUSR," >> $outfile
  echo "  \"vCpuTimeKernelMode\": $CPUKRN," >> $outfile
  echo "  \"tvCpuTimeKernelMode\": $T_CPUKRN," >> $outfile
  echo "  \"vCpuIdleTime\": $CPUIDLE," >> $outfile
  echo "  \"tvCpuIdleTime\": $T_CPUIDLE," >> $outfile
  echo "  \"vCpuTimeIOWait\": $CPUIOWAIT," >> $outfile
  echo "  \"tvCpuTimeIOWait\": $T_CPUIOWAIT," >> $outfile
  echo "  \"vCpuTimeIntSrvc\": $CPUIRQ," >> $outfile
  echo "  \"tvCpuTimeIntSrvc\": $T_CPUIRQ," >> $outfile
  echo "  \"vCpuTimeSoftIntSrvc\": $CPUSOFTIRQ," >> $outfile
  echo "  \"tvCpuTimeSoftIntSrvc\": $T_CPUSOFTIRQ," >> $outfile
  echo "  \"vCpuContextSwitches\": $CSWITCH," >> $outfile
  echo "  \"tvCpuContextSwitches\": $T_CSWITCH," >> $outfile
  echo "  \"vCpuNice\": $CPUNICE," >> $outfile
  echo "  \"tvCpuNice\": $T_CPUNICE," >> $outfile
  echo "  \"vCpuSteal\": $CPUSTEAL," >> $outfile
  echo "  \"tvCpuSteal\": $T_CPUSTEAL," >> $outfile
  echo "  \"vDiskSuccessfulReads\": $COMPLETEDREADS," >> $outfile
  echo "  \"vDiskMergedReads\": $MERGEDREADS," >> $outfile
  echo "  \"vDiskReadTime\": $READTIME," >> $outfile
  echo "  \"vDiskSuccessfulWrites\": $COMPLETEDWRITES," >> $outfile
  echo "  \"vDiskMergedWrites\": $MERGEDWRITES," >> $outfile
  echo "  \"vDiskWriteTime\": $WRITETIME," >> $outfile

  echo "  \"vMemoryTotal\": $MEMTOT," >> $outfile     # KB
  echo "  \"vMemoryFree\": $MEMFREE," >> $outfile     # KB
  echo "  \"vMemoryBuffers\": $BUFFERS," >> $outfile  # KB
  echo "  \"vMemoryCached\": $CACHED," >> $outfile    # KB


  echo "  \"vLoadAvg\": $LAVG," >> $outfile
  echo "  \"vId\": \"$vmid\"," >> $outfile
  echo "  \"vCpuType\": \"$CPUTYPE\"," >> $outfile
  echo "  \"tvCpuType\": $T_CPUTYPE," >> $outfile
  echo "  \"vCpuMhz\": \"$CPUMHZ\"," >> $outfile

  if [ $CONTAINER = true ] || [ $PROCESS = true ];
  then
  	echo "  \"tvCpuMhz\": $T_CPUMHZ," >> $outfile
  else
	echo "  \"tvCpuMhz\": $T_CPUMHZ" >> $outfile
fi


## Container level metrics
if [ $CONTAINER = true ]
then
  #echo "CONTAINER is Running!!"
  T_CNT_1=$(date +%s%3N)

  echo "  \"cMetricType\": \"Container level\"," >> $outfile

  # Get CPU stats

  CPUUSRC=$(cat /sys/fs/cgroup/cpuacct/cpuacct.stat | grep 'user' | cut -d" " -f 2) # in cs
  T_CPUUSRC=$(date +%s%3N)

  CPUKRNC=$(cat /sys/fs/cgroup/cpuacct/cpuacct.stat | grep 'system' | cut -d" " -f 2) # in cs
  T_CPUKRNC=$(date +%s%3N)

  CPUTOTC=$(cat /sys/fs/cgroup/cpuacct/cpuacct.usage) # in ns
  T_CPUTOTC=$(date +%s%3N)

  IFS=$'\n'

  PROS=(`cat /proc/cpuinfo | grep 'processor' | cut -d":" -f 2`)
  NUMPROS=${#PROS[@]}
  T_NUMPROS=$(date +%s%3N)


  # Get disk stats

  # Get disk major:minor numbers, store them in disk_arr
  # Grep disk first using lsblk -a, find type "disk" and then find the device number
  IFS=$'\n'
  lines=($(lsblk -a | grep 'disk'))
  unset IFS
  disk_arr=()
  for line in "${lines[@]}"
  do 
    temp=($line)
    disk_arr+=(${temp[1]})
  done


  arr=($(cat /sys/fs/cgroup/blkio/blkio.sectors | grep 'Total' | cut -d" " -f 2))

  # if arr is empty, then assign 0; else, sum up all elements in arr
  if [ -z "$arr" ]; then
    SRWC=0
  else
    SRWC=$( ( IFS=+; echo "${arr[*]}" ) | bc )
  fi


  IFS=$'\n'
  arr=($(cat /sys/fs/cgroup/blkio/blkio.throttle.io_service_bytes  | grep 'Read')) # in Bytes
  unset IFS

  if [ -z "$arr" ]; then
    BRC=0
  else
    BRC=0
    for line in "${arr[@]}"
    do 
      temp=($line)
      for elem in "${disk_arr[@]}"
      do 
        if [ "$elem" == "${temp[0]}" ]
        then
          BRC=$(echo "${temp[2]} + $BRC" | bc)
        fi
      done
    done
  fi



  IFS=$'\n'
  arr=($(cat /sys/fs/cgroup/blkio/blkio.throttle.io_service_bytes  | grep 'Write')) # in Bytes
  unset IFS

  if [ -z "$arr" ]; then
    BWC=0
  else
    BWC=0
    for line in "${arr[@]}"
    do 
      temp=($line)
      for elem in "${disk_arr[@]}"
      do 
        if [ "$elem" == "${temp[0]}" ]
        then
          BWC=$(echo "${temp[2]} + $BWC" | bc)
        fi
      done
    done
  fi


  # Get network stats

  NET=(`cat /proc/net/dev | grep 'eth0'`)
  NRC=${NET[1]}  # bytes received
  [[ -z "$NRC" ]] && NRC=0

  NTC=${NET[9]}  # bytes transmitted
  [[ -z "$NTC" ]] && NTC=0


  #Get container ID
  CIDS=$(cat /etc/hostname)

  # Get memory stats
  MEMUSEDC=$(cat /sys/fs/cgroup/memory/memory.usage_in_bytes)
  MEMMAXC=$(cat /sys/fs/cgroup/memory/memory.max_usage_in_bytes)

  unset IFS
  CPUPERC=(`cat /sys/fs/cgroup/cpuacct/cpuacct.usage_percpu`) # in ns, 0, 1, 2, 3 elements
  T_CPUPERC=$(date +%s%3N)

  T_CNT_2=$(date +%s%3N)
  let T_CNT=$T_CNT_2-T_CNT_1

  cPGFault=$(filedata "/sys/fs/cgroup/memory/memory.stat" "pgfault")
  cMajorPGFault=$(filedata "/sys/fs/cgroup/memory/memory.stat" "pgmajfault")


  # print container level data
  echo "  \"cTime\": $T_CNT, " >> $outfile
  echo "  \"cCpuTime\": $CPUTOTC," >> $outfile     # ns
  echo "  \"tcCpuTime\": $T_CPUTOTC," >> $outfile
  echo "  \"cNumProcessors\": $NUMPROS," >> $outfile
  echo "  \"cPGFault\": $cPGFault," >> $outfile
  echo "  \"cMajorPGFault\": $cMajorPGFault," >> $outfile
  echo "  \"tcNumProcessors\": $T_NUMPROS," >> $outfile
  echo "  \"cProcessorStats\": {" >> $outfile
  for (( i=0; i<NUMPROS; i++ ))
  do 
    echo "  \"cCpu${i}TIME\": ${CPUPERC[$i]}, " >> $outfile
  done
  echo "  \"tcCpu#TIME\": $T_CPUPERC," >> $outfile
  echo "  \"cNumProcessors\": $NUMPROS" >> $outfile
  echo "  }," >> $outfile

  echo "  \"cCpuTimeUserMode\": $CPUUSRC," >> $outfile    # cs
  echo "  \"tcCpuTimeUserMode\": $T_CPUUSRC," >> $outfile
  echo "  \"cCpuTimeKernelMode\": $CPUKRNC," >> $outfile  # cs
  echo "  \"tcCpuTimeKernelMode\": $T_CPUKRNC," >> $outfile

  echo "  \"cDiskSectorIO\": $SRWC," >> $outfile
  echo "  \"cDiskReadBytes\": $BRC," >> $outfile
  echo "  \"cDiskWriteBytes\": $BWC," >> $outfile

  echo "  \"cNetworkBytesRecvd\": $NRC," >> $outfile
  echo "  \"cNetworkBytesSent\": $NTC," >> $outfile

  echo "  \"cMemoryUsed\": $MEMUSEDC," >> $outfile
  echo "  \"cMemoryMaxUsed\": $MEMMAXC," >> $outfile


  echo "  \"cId\": \"$CIDS\"," >> $outfile
  echo "  \"cNumProcesses\": $PIDS," >> $outfile


  if [ $PROCESS = true ];
  then
    echo "  \"pMetricType\": \"Process level\"," >> $outfile
  else
    echo "  \"pMetricType\": \"Process level\"" >> $outfile
fi
fi

## Process level metrics

if [ $PROCESS = true ]
then
  #echo "PROCESS is Running!!"

  T_PRC_1=$(date +%s%3N)
  # For each process, parse the data

  # command cat $outfile in the last line of the script
  # and ./rudataall.sh are counted as 2 extra processes, so -2 here for PIDS

  echo "  \"pProcesses\": [" >> $outfile

  for (( i=0; i<PIDS; i++ ))
  do 
    pid=${PPS[i]}
    #check if pid still exists
    STAT=(`cat /proc/$pid/stat 2>/dev/null`)
    if (( ${#STAT[@]} )); then
	  PID=${STAT[0]}
	  PSHORT=$(echo $(echo ${STAT[1]} | cut -d'(' -f 2 ))
	  PSHORT=${PSHORT%?}
	  NUMTHRDS=${STAT[19]}

	  # Get process CPU stats
	  UTIME=${STAT[13]}
	  STIME=${STAT[14]}
	  CUTIME=${STAT[15]}
	  CSTIME=${STAT[16]}
	  TOTTIME=$((${UTIME} + ${STIME}))

	  # context switch  !! need double check result format
	  VCSWITCH=$(cat /proc/$pid/status | grep "^voluntary_ctxt_switches" | \
        cut -d":" -f 2 | sed 's/^[ \t]*//') 
	  NVCSSWITCH=$(cat /proc/$pid/status | grep "^nonvoluntary_ctxt_switches" | \
        cut -d":" -f 2 | sed 's/^[ \t]*//') 

	  # Get process disk stats
	  DELAYIO=${STAT[41]}
	  pPGFault=$(cat /proc/$pid/stat | cut -d' ' -f 10)
	  pMajorPGFault=$(cat /proc/$pid/stat | cut -d' ' -f 12)

	  # Get process memory stats
	  VSIZE=${STAT[22]} # in Bytes
	  RSS=${STAT[23]} # in pages

	  PNAME=$(cat /proc/$pid/cmdline | tr "\0" " ")
	  PNAME=${PNAME%?}

	  # print process level data
	  echo "  {" >> $outfile
	  echo "  \"pId\": $PID, " >> $outfile
	  
      if jq -e . >/dev/null 2>&1 <<<"$PNAME"; then
		:
	  else
		pCmdLine="Invalid Json"
	  fi


	  echo "  \"pCmdLine\":\"$PNAME\", " >> $outfile                    # process cmdline
	  echo "  \"pName\":\"$PSHORT\", " >> $outfile          # process cmd short version
	  echo "  \"pNumThreads\": $NUMTHRDS, " >> $outfile
	  echo "  \"pCpuTimeUserMode\": $UTIME, " >> $outfile         # cs
	  echo "  \"pCpuTimeKernelMode\": $STIME, " >> $outfile       # cs
	  echo "  \"pChildrenUserMode\": $CUTIME, " >> $outfile       # cs
	  echo "  \"pPGFault\": $pPGFault, " >> $outfile 
	  echo "  \"pMajorPGFault\": $pMajorPGFault, " >> $outfile 
	  echo "  \"pChildrenKernelMode\": $CSTIME, " >> $outfile     # cs
	  if  [ -z "$VCSWITCH" ];
	  then
		VCSWITCH="NA"
	  fi
	  echo "  \"pVoluntaryContextSwitches\": $VCSWITCH, " >> $outfile
	  if  [ -z "$NVCSSWITCH" ];
	  then
		NVCSSWITCH="NA"
	  fi
	  echo "  \"pNonvoluntaryContextSwitches\": $NVCSSWITCH, " >> $outfile
	  echo "  \"pBlockIODelays\": $DELAYIO, " >> $outfile         # cs
	  echo "  \"pVirtualMemoryBytes\": $VSIZE, " >> $outfile
	  echo "  \"pResidentSetSize\": $RSS " >> $outfile            # page
	  echo "  }, " >> $outfile
   fi	
  done
  T_PRC_2=$(date +%s%3N)
  let T_PRC=$T_PRC_2-$T_PRC_1
  echo "  {\"cNumProcesses\": $PIDS," >> $outfile
  echo "  \"pTime\": $T_PRC }" >> $outfile
  echo "  ]" >> $outfile
fi

echo "}" >> $outfile

cat $outfile





