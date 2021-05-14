#!/bin/bash
[[  "$DEBUG" == "y" ]] && set -x
#default variables for port and host#
port='11211'
ip='127.0.0.1'
#functions
mc_usage() {
	echo "Usage:
	Specify host and port after the command, default is localhost and 11211
	-F|--flush
	-s|--status
	-H|--host [IP]
	-P|--port
	-h|--help (print this message)
	-f|--fill (ttl)
	-b|--backup (file_name)
	-r|--restore (file_name)"
}

mc_read(){
	while IFS=$'\r' read -u "$fd" -r -a response; do
		case "${response[0]}" in
			VALUE)
				echo -ne "${response[@]}"
				size="${response[3]}"
				read -u "$fd" -N "${size}" -r response
				echo -en "${response}"
			;;
			ERROR)
				echo "key has failed"
				break

			;;
			OK|STORED|END)
				break
			;;
			*)
				echo "${response[@]}"
			;;
		esac
	done
}

mc_connect(){
	exec {fd}<>/dev/tcp/${ip}/${port} 
}

mc_close(){
	exec {fd}<&- 
}

mc_send(){
	echo -ne "$1\r\n" >&${fd}
}

mc_fill(){
	echo "adding 10k keys, might take a while...make yourself a coffee"
	for i in {0..99}; do 
		mc_send "set key${i} 0 ${ttl} $(( ${#i} + 3))\r\nval${i}"		
		mc_read
	done 
	echo "keys have been added"
}
mc_status(){
	echo "getting full status from ${ip} on ${port}"
	mc_send "stats"  
	mc_read
}

mc_quit(){
	mc_send "quit"
}


mc_flush(){
		mc_send "flush_all"
		echo "keys have been flushed"
}

mc_args(){
	while [[  $# -gt 0  ]]; do
		case "$1" in
			-H|--host)
			ip="$2"
			shift
		;;

			-P|--port)
			port="$2"
			shift
		;;
		esac
		shift
	done
}

mc_get(){
	mc_send "get ${1}"
}

mc_key_params(){
	mc_send "lru_crawler metadump all"
	params=$(mc_read) 
}
mc_backup(){
	mc_key_params
	keylist=$(echo "$params" | awk -F= '{print $2}' | cut -d ' ' -f 1)
	for keys in ${keylist[@]}; do 
		mc_get "$keys" 
		mc_read >> "$backup_file"
	done
}
mc_restore(){
	echo "restoring dataset...."
	while read -r file
        do
		dataset=(${file})
		key="${dataset[1]}"
		flags="${dataset[2]}"
		size="${dataset[3]}"
		bytes=$(( $size +2 ))
		read -N "${size}" -r second_line	
		value="${second_line}"
		read -r empty_line
		echo "$key"
		echo "$bytes"
		echo "$value"
		mc_send "set ${key} ${flags} 0 ${size}\r\n${value}"
		mc_read
        done < "$restore_file" || exit 2
	echo "success!"
}

#################
#start of script#
#################
if [[ $# -eq 0 ]]; then
	mc_usage && exit
fi
operation="$1"
shift
mc_args "$@"
if ! mc_connect 2>/dev/null ; then 
echo "Could not connect to memcached on ${ip}:${port}"
exit 101
fi
case "$operation" in
	
	-F|--flush)
		mc_flush "$@"
	;;
	-s|--status)
		mc_status "$@"
	;;
	-h|--help)
		mc_usage "$@"
	;;
	-f|--fill)
		if [[ $# -eq 0 ]]; then
			ttl="0"
			echo "no value has been passed, defaulting ttl to 0" 
			mc_fill	
	        else	
			ttl="$1"
			echo "ttl has been set to ${ttl}"
			mc_fill
		fi
	;;
	-b|--backup)
		if [[ $# -eq 0 ]]; then
			mc_usage
		else
			backup_file="$1"
            		if [[ -f $backup_file ]]; then
                		echo "file ${backup_file} exists"
				exit 17 
      	 		else
               			mc_backup && echo "success!"
			fi 
		fi
	;;
	-r|--restore)
		if [[ $# -eq 0 ]]; then
			mc_usage  
		else
			restore_file="$1"
			mc_restore "restore_file"
		fi
	;;
	
esac
mc_close
