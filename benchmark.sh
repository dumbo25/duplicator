#!/bin/bash

# from a comment by Rive in the URL https://www.raspberrypi.org/forums/viewtopic.php?f=63&t=141129&start=25
# sudo chmod +x benchmark.sh
# run as: sudo ./benchmark.sh

# sudo ./benchmark.sh 512 /mnt/usb_1 /test/test.dat
# arg 1: number of MB 
# arg 2: device
# arg 3: path and filename

DATAMB=${1:-512}
DEVICE=${2:-/dev/mmcblk0}
FILENM=${3:-~/test.dat}
[ -f /flash/config.txt ] && CONFIG=/flash/config.txt || CONFIG=/boot/config.txt

trap "rm -f ${FILENM}" EXIT

[ "$(whoami)" == "root" ] || { echo "Must be run as root!"; exit 1; }

HDCMD="hdparm -t --direct $DEVICE | grep Timing"
WRCMD="rm -f ${FILENM} && sync && dd if=/dev/zero of=${FILENM} bs=1M count=${DATAMB} conv=fsync 2>&1 | grep -v records"
RDCMD="echo 3 > /proc/sys/vm/drop_caches && sync && dd if=${FILENM} of=/dev/null bs=1M 2>&1 | grep -v records"

# not using OpenELEC, but this is required for proper calculation of READ and WRITE times
grep OpenELEC /etc/os-release >/dev/null && DDTIME=5 || DDTIME=6

getperfmbs()
{
  local cmd="${1}" fcount="${2}" ftime="${3}" bormb="${4}"
  local result count _time perf

  result="$(eval "${cmd}")"
  count="$(echo "${result}" | awk "{print \$${fcount}}")"
  _time="$(echo "${result}" | awk "{print \$${ftime}}")"
  if [ "${bormb}" == "MB" ]; then
    perf="$(echo "${count}" "${_time}" | awk '{printf("%0.2f", $1/$2)}')"
  else
    # dd calculates MB using 1,000x1,0000. This was using 1024x1024
    # So, the READ / WRITE numbers were not an average
    perf="$(echo "${count}" "${_time}" | awk '{printf("%0.2f", $1/$2/1000/1000)}')"
  fi
  echo "${perf}"
  echo "${result}" >&2
}

getavgmbs()
{
  echo "${1} ${2} ${3}" | awk '{r=($1 + $2 + $3)/3.0; printf("%0.2f MB/sec",r)}'
}

# not running kodi
# systemctl stop kodi 2>/dev/null
clear
sync

[ -f /sys/kernel/debug/mmc0/ios ] || mount -t debugfs none /sys/kernel/debug

overlay="$(grep -E "^dtoverlay" ${CONFIG} | grep -E "mmc|sdhost")"
clock="$(grep "actual clock" /sys/kernel/debug/mmc0/ios 2>/dev/null | awk '{printf("%0.3f MHz", $3/1000000)}')"
core_now="$(vcgencmd measure_clock core | awk -F= '{print $2/1000000}')"
core_max="$(vcgencmd get_config int | grep core_freq | awk -F= '{print $2}')"
turbo="$(vcgencmd get_config int | grep force_turbo | awk -F= '{print $2}')"
[ -n "${turbo}"    ] || turbo=0
[ ${turbo} -eq 0 ]   && turbo="$(cat /sys/devices/system/cpu/cpufreq/ondemand/io_is_busy)"
[ -n "${core_max}" ] || core_max="${core_now}"

echo "Settings:"
echo "========"
echo "CONFIG: ${overlay}"
echo "CLOCK : ${clock}"
echo "CORE  : ${core_max} MHz, turbo=${turbo}"
echo "DATA  : ${DATAMB} MB"
echo "FILE  : $FILENM"
echo "DEVICE: $DEVICE"

echo
echo "HDPARM:"
echo "======"
HD1="$(getperfmbs "${HDCMD}" 5 8 MB)"
HD2="$(getperfmbs "${HDCMD}" 5 8 MB)"
HD3="$(getperfmbs "${HDCMD}" 5 8 MB)"
HDA="$(getavgmbs "${HD1}" "${HD2}" "${HD3}")"

echo
echo "WRITE:"
echo "====="
WR1="$(getperfmbs "${WRCMD}" 1 ${DDTIME} B)"
WR2="$(getperfmbs "${WRCMD}" 1 ${DDTIME} B)"
WR3="$(getperfmbs "${WRCMD}" 1 ${DDTIME} B)"
WRA="$(getavgmbs "${WR1}" "${WR2}" "${WR3}")"

echo
echo "READ:"
echo "===="
RD1="$(getperfmbs "${RDCMD}" 1 ${DDTIME} B)"
RD2="$(getperfmbs "${RDCMD}" 1 ${DDTIME} B)"
RD3="$(getperfmbs "${RDCMD}" 1 ${DDTIME} B)"
RDA="$(getavgmbs "${RD1}" "${RD2}" "${RD3}")"

echo 
echo "AVERAGE:"
echo "======="
printf "HDPARM = %10s   WRITE = %10s    READ = %10s\n" "${HDA}" "${WRA}" "${RDA}"
