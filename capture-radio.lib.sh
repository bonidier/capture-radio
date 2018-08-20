#!/bin/bash
#
# author: Didier BONNEFOI <dbonnefoi@gmail.com>
# Library to capture audio streams from (web)radio playlists
#
# see README file for usage
#


FILE_LIST=radio-list.txt

BIN_WGET=$(command -v wget)

OUTPUT_DIR=./captured
WORK_DIR=./working
LOG_DIR=./logs
DB_DIR=./db
CAPTURE_RADIO_STREAMING=
WGET_UA="Winamp/5.x"
CMD_WGET=("${BIN_WGET}" -U "${WGET_UA}")
_WGET_PID=

CAPTURE_VERSION=1.0

# trap kill or CTRL+C signals,
# otherwise, the capture will continue indefitely...
trap capture_onexit SIGINT TERM

#
# convert input value to seconds
# usage: capture_time_to_seconds [0-9]+[hms|]
# echo converted value
#
capture_time_to_seconds()
{
  local val=$1
  local multiply valonly lastchar

  # get numeric value
  valonly=$(echo "${val}" | grep -Eo '^[0-9]+')
  # get last char if the input value
  lastchar=$(echo "${val}" | grep -Eo ".$")

  case ${lastchar} in
    h) multiply=3600;;
    m) multiply=60;;
    *) multiply=1;;
  esac

  echo $((valonly * multiply))
}


capture_onexit()
{
  echo -e '\n\n /!\ trapped, stopping capture NOW ! /!\\\ \n'
  capture_stop
  exit $?
}


capture_echo_fail()
{
  echo "[error]:$1"
}

# embedded help content
capture_help()
{
  cat <<EOF
CAPTURE-RADIO ${CAPTURE_VERSION}

* current help
  $0 -h

* options with arguments

  -t    uniq tag name for a radio, should match '-a-zA-Z0-9_' to be catched
  -d    capture duration (seconds by default)
        if you need a long capture time,
        you can suffix value with one of these units: h,m,s (hours, minutes, seconds)
        example: 10m

  -s    stream number to capture if your defined playlist containing many streams

* get available tags (radios list)
  $0 -l

* get available streams for a tag
  $0 -t [radio_tag]

* launch capture of a radio
  $0 -t [radio_tag] -d [capture duration]

  if the radio's playlist has many streams, will show them instead of starting

* launch capture of a defined radio's stream
  $0 -t [radio_tag] -d [capture duration] -s [stream_number]

EOF
  exit 1
}

capture_get_streams()
{
  local radio_url=$1
  local stream_id=$2
  local pl_cache_file
  local pl_cache_streams
  local pl_hash
  local pl_ext

  if [ $# -eq 0 ]; then
    capture_echo_fail "no URL defined"
    return 1
  fi

  # determine if url is a playlist
  pl_ext=$(echo "${radio_url}" | grep -Eo ".(m3u|pls)$" )

  # it's a playlist
  if [ ! -z "${pl_ext}" ]; then
    # that should be a playlist
    pl_hash=$(echo "${radio_url}" | md5sum | cut -d ' ' -f1)
    pl_cache_file="${DB_DIR}/${pl_hash}.url"
    pl_cache_streams="${DB_DIR}/${pl_hash}.streams"

    if [ ! -f "${pl_cache_file}" ]; then
      # removing CR from windows server remote files if necessary
      ${CMD_WGET[*]} "${radio_url}" -q -O- | tr -d '\r' > "${pl_cache_file}"
    fi
    # writing file with all streams present in the playlist
    grep -Eo 'http://.+' "${pl_cache_file}" > "${pl_cache_streams}"

    capture_stream_choice "${pl_cache_streams}" "${stream_id}"
  else
    # that's a audio flow, no choice
    CAPTURE_RADIO_STREAMING="${radio_url}"
    echo "1 stream: ${CAPTURE_RADIO_STREAMING}"
  fi

}

#
# allow user to select wanted streaming URL
#
# capture_stream_choice file_streams stream_id
capture_stream_choice()
{

  # file containing streams URL
  local file_streams=$1
  # stream id to capture
  local stream_id=$2

  # total streams found
  local count=
  # just a flag to display selected stream
  local selected_flag=

  # verify if file exists and containing streams URL
  if [ ! -f "${file_streams}" ]; then
    capture_echo_fail "streams file missing"
    return 1
  else
    if ! count=$(grep -c '^http://' "${file_streams}"); then
      capture_echo_fail "no streams in file"
      return 1
    fi
  fi

  echo "Streams found: ${count}"

  # if only one stream, autoselect him
  [ "${count}" == "1" ] && stream_id=1

  # if stream_id defined
  if [ ! -z "${stream_id}" ]; then
    if [[ ! ${stream_id} =~ ^[0-9]+$ ]]; then
      capture_echo_fail "Stream ID should be numeric value"
    fi
    if [ "${stream_id}" -gt "${count}" ]; then
      capture_echo_fail "Stream ID too high, ${count} maximum"
      return 1
    fi
  fi

  echo "streams URL from playlist:"

  local url=
  local idx=0

  while read -r url
  do
    selected_flag="-"
    idx=$(( idx + 1 ))

    # stream ID to capture
    if [ "${stream_id}" == "${idx}" ]; then
       selected_flag="X"
       CAPTURE_RADIO_STREAMING="${url}"
    fi

    echo "${idx}) [${selected_flag}] ${url}"

  done < "${file_streams}"

}

#
# if no argument, return valid tag list,
# if argument "check", return duplicate tags entries and fail
# capture_get_tags_list [check|]
#
capture_get_tags_list()
{

  local check=$1
  local tag_list
  local duplicated_tags

  tag_list=$(grep -v '^$' "${FILE_LIST}" | awk -F'|' '{print $1}' | grep -E '^[-a-zA-Z0-9_]+$' | sort)

  if [ "${check}" == "check" ]; then

    # extract duplicate tags
    duplicated_tags=$(echo "${tag_list}" | tr ' ' '\n' | uniq -d)
    # fail if duplicate tags present
    if [ ! -z "${duplicated_tags}" ]; then
       capture_echo_fail "duplicate tags, check your ${FILE_LIST}"
       echo "duplicate tags: ${duplicated_tags}"
       return 1
    fi

  else
    echo "${tag_list}" | tr ' ' '\n'
  fi

  if [ -z "${tag_list}" ]; then
    capture_echo_fail "no valid tag in your ${FILE_LIST}"
    return 1
  fi

}

#
# return url linked to a tag
# usage: capture_get_tag_url <tagname>
#
capture_get_tag_url()
{
  local tag=$1
  grep "^${tag}|" "${FILE_LIST}" | awk -F'|' '{print $2}'

}

capture_init()
{

  [ ! -d "${OUTPUT_DIR}" ] && mkdir "${OUTPUT_DIR}"
  [ ! -d "${WORK_DIR}" ] && mkdir "${WORK_DIR}"
  [ ! -d "${LOG_DIR}" ] && mkdir "${LOG_DIR}"
  [ ! -d "${DB_DIR}" ] && mkdir "${DB_DIR}"

  WKFILE="${WORK_DIR}/capture.$$"

  if [ ! -f "$FILE_LIST" ]; then
    capture_echo_fail "$FILE_LIST is missing"
    return 1
  else
    capture_get_tags_list check || return 1
  fi

  return 0

}

#
# parse program options
# usage: capture_getopts $@
#
capture_getopts()
{
  local o

  while getopts "vhlt:d:s:" o; do
    case $o in
      h) capture_help;;
      v);;
      t)
        CAPTURE_PREFIX=${OPTARG}
        CAPTURE_RADIO_URL=$(capture_get_tag_url "${CAPTURE_PREFIX}")
        ;;
      s) CAPTURE_STREAM_ID=${OPTARG};;
      l) capture_get_tags_list; return 1;;
      d) CAPTURE_TIME=${OPTARG} ;;
      *)
        echo "bad argument: ${OPTARG}"
        exit 1
        ;;
    esac
  done

  # if required options are not defined, show help
  if [ -z "${CAPTURE_PREFIX}" ]; then
    capture_help
  fi
}

capture_bootstrap()
{

  capture_init || return 1
  capture_getopts "$@" || return 1
  # remove all getopts arguments
  shift $((OPTIND-1))

  if [ -z "$CAPTURE_RADIO_URL" ]; then
    capture_echo_fail "tag not found"
    return 1
  fi

  capture_get_streams "${CAPTURE_RADIO_URL}" "${CAPTURE_STREAM_ID}"
  # if capture time defined, check value validity
  if [ ! -z "${CAPTURE_TIME}" ]; then
    # unit can be in hour, minutes, or seconds
    # (seconds if no unit)
    if [[ ! ${CAPTURE_TIME} =~ ^[0-9]+[hms]?$ ]]; then
      capture_echo_fail "capture time is invalid, check help"
      return 1
    else
      # set the unit to seconds if nothing, only for debug output about time to capture
      [[ ${CAPTURE_TIME} =~ ^[0-9]+$ ]] && CAPTURE_TIME=${CAPTURE_TIME}s
    fi
  else
     # if no capture time defined, just want get streams in playlist
    return
  fi

  local retries=0

  # start time in timestamp
  local ts_start=
  # end time in timestamp
  local ts_end=
  # current time in timestamp
  local ts_now=
  # convert input capture-time to seconds
  local ctime_seconds

  ctime_seconds=$(capture_time_to_seconds "${CAPTURE_TIME}")

  ts_start=$(date +%s)
  ts_end=$(( ts_start + ctime_seconds ))

   # if failing to start, url is missing, stopping now !
  capture_start || return 1

  echo "capture will stop at: $(date -d @${ts_end})"

  #### main capture process ####
  local percent=
  ts_now=${ts_start}
  while [ "${ts_now}" -lt "${ts_end}" ]
  do
    ts_now=$(date +%s)
    elapsed=$((ts_now - ts_start))
    remaining=$((ts_end - ts_now))

    # is wget process PID always here ?
    if ! capture_is_running; then
       capture_echo_fail "capture is not running, trying restart"
       # do not loop to many times...
       retries=$(( retries + 1 ))
       # if more than 3 fail, stop the capture
       if [ ${retries} -eq 3 ]; then
         capture_echo_fail "too many failures, stopping"
         break
       fi
       capture_stop
       capture_start
    else
       # progression inline
       percent=$((elapsed * 100 / ctime_seconds))
       echo -n  "progression:$(printf "%02d%%" ${percent}) [time spent: elapsed=${elapsed} / remaining=${remaining} ]"

       if [ ${remaining} -gt 0 ]; then
         echo -ne '\r'
         # healthcheck offset
         sleep 0.5
       else
         # quit the healthcheck at the end of the capture
         echo -e "\\nIt's time to stop the capture!\\n"
         break
       fi
    fi
  done
  capture_stop
  return $?
}

capture_is_running()
{
  # no wget PID, no capture in progress
  if [ -z "${_WGET_PID}" ]; then
    return 1
  fi

  # is wget process PID always here ?
  pgrep -f "${BIN_WGET}" | grep -q "^${_WGET_PID}$"
  return $?
}

capture_start()
{
  if [ -z "${CAPTURE_RADIO_STREAMING}" ]; then
     capture_echo_fail "no radio streaming defined"
     return 1
  fi

  cat <<EOF
== capture in progress ==
playlist address: '${CAPTURE_RADIO_URL}'
getting sound from address: '${CAPTURE_RADIO_STREAMING}'
streaming capture in progress in: ${WKFILE}
capture duration: $CAPTURE_TIME
EOF

  ${CMD_WGET[*]} -c --timeout=3 "${CAPTURE_RADIO_STREAMING}" -O "${WKFILE}" -o/dev/null &
  _WGET_PID=$!

  echo "wget_pid=${_WGET_PID}"
  dt_start=$(date '+%Y-%m-%d_%H-%M-%S')
  echo "started at: ${dt_start}"

  return 0
}


capture_stop()
{
  # no buffer file present ?
  if [ ! -f "${WKFILE}" ]; then
     capture_echo_fail "capture file missing"
     return 1
  fi

  dt_end=$(date '+%Y-%m-%d_%H-%M-%S')

  echo "capture end at: ${dt_end}"
  if [ -n "${_WGET_PID}" ]; then
    echo "killing wget PID: ${_WGET_PID}"
    kill ${_WGET_PID} && echo "${_WGET_PID} killed"
  fi

  # if buffer file is empty, remove and quit
  if [ ! -s "${WKFILE}" ]; then
    capture_echo_fail "capture file is empty, removing"
    rm -f "${WKFILE}"
    return 1
  fi

  ### search audio extension, if matching
  local capture_ext
  capture_ext=$(echo "${CAPTURE_RADIO_STREAMING}" | grep -Eo ".(mp3|aac|ogg)$")

  # can't find extension in stream url ?
  if [ -z "${capture_ext}" ]; then
   echo "stream didn't get extension, trying to find it..."
   # trying to find file type
   local ftype
   ftype=$(file -b "${WKFILE}" | grep -Eo 'layer III|AAC|Ogg' )
   case ${ftype} in
     "layer III") capture_ext=".mp3";;
     "AAC") capture_ext=".aac";;
     "Ogg") capture_ext=".ogg";;
     *) capture_ext=".put_the_good_extension_yourself";;
   esac
  fi
  echo "estimated extension:${capture_ext}"
  ###

  # a directory for each radio tag
  local output_subdir="${OUTPUT_DIR}/${CAPTURE_PREFIX}"
  [ ! -d "${output_subdir}" ] && mkdir "${output_subdir}"

  local output="${output_subdir}/${CAPTURE_PREFIX}.from_${dt_start}_to_${dt_end}${capture_ext}"

  mv "${WKFILE}" "${output}"
  echo "output file: ${output}"

  return 0
}
