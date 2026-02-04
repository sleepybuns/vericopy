#!/bin/bash

debug=1 # debug mode records logs
mock=0 # mock mode does not do any file operations 
bar_size=$(( $(tput cols) -  10 ))
bar_char_done="|"
bar_char_todo="-"
bar_percentage_scale=2

dest=$( realpath "${!#}" )
logs="/dev/null"
declare -A dir_table
declare -A file_table
declare -i bytes=0
declare -i count=0
declare -i total_bytes=0
declare -i diff=0
declare -i total_cols=0
declare -i prev_msg_height=0
declare -i next_msg_height=0
declare -i total_rows=0
declare -i curr_row=0
declare -i boundary=0

print_msg() {
    msg=$1
    total_cols=$( tput cols )
    next_msg_height=$(( ${#msg} / $total_cols ))

    tput hpa 0 
    # # erase the previous message
    # for ((x=0; x<$prev_msg_height + 1 ; x++ )); do
    #     tput cuu1 && tput el  
    # done

    # read '\e[6n' as a prompt it prints ESC[row;col]R (displayed as '^[[17;1R') 
    # read until delimiter 'R' then put in array 'pos'. 
    # -r ignore backslash as escape character
    # -s silent output 
    # array 'pos' is split by "[;" so we get [ESC, row, col] 
    IFS="[;" read -p $'\e[6n' -d R -a pos -rs  
    curr_row=${pos[1]}
    total_rows=$( tput lines )
    boundary=$(( $total_rows - $next_msg_height - 1 ))

    if [[  $boundary -lt $curr_row ]]; then  
        diff=$(( $curr_row - $boundary ))
        tput indn $diff
        tput cuu $diff
    fi
    tput il $(( $next_msg_height + 1 ))

    # if [ $next_msg_height -gt $prev_msg_height ]; then 
    #     diff=$(( $next_msg_height - $prev_msg_height ))
    #     tput indn $diff
    #     tput cuu $diff
    #     tput il $diff
    # elif [ $prev_msg_height -gt $next_msg_height ]; then 
    #     diff=$(( $prev_msg_height - $next_msg_height ))
    #     tput dl $diff 
    #     tput rin $diff 
    #     tput cud $diff
    # fi 
    echo -e "$msg" | tee >(cat >&1) >>$logs
    prev_msg_height=$next_msg_height
    # for ((x=0; x<$prev_msg_height + 1; x++ )); do 
    #     echo -ne "$2" 
    # done

    # if [[ -n $2 ]]; then 
    #     for ((x=0; x<$prev_msg_height + 1; x++ )); do 
    #         sleep 1
    #         tput indn 1
    #         tput cuu 1
    #         tput il 1 
    #         tput cud 1
    #     done
    # fi
    sleep 0.2    
}

show_progress() {
    current="$1"
    total="$2"
    percent=$(bc <<< "scale=$bar_percentage_scale; 100 * $current / $total" )
    done=$(bc <<< "scale=0; $bar_size * $percent / 100" )
    todo=$(bc <<< "scale=0; $bar_size - $done" )
    done_sub_bar=$(printf "%${done}s" | tr " " "${bar_char_done}")
    todo_sub_bar=$(printf "%${todo}s" | tr " " "${bar_char_todo}")
    echo -n "[${done_sub_bar}${todo_sub_bar}] ${percent}%"
    tput hpa 0
    sleep 0.2
}

verify() {
    print_msg "Verifying: $2" 
    og=($( md5sum "$1" ))
    if [[ $mock == 0 ]]; then 
        yg=($( md5sum "$2" ))
        cmp -s <( printf ${og[0]} ) <( printf ${yg[0]} )
    else
        cmp -s <( printf ${og[0]} ) <( printf ${og[0]} )        
    fi
}

m_mkdir() {
    print_msg "Creating directories: $1" 
    if [[ $mock == 0 ]]; then mkdir "$1" 2>$logs; fi
}

m_cp() {
    print_msg "Copying: $1 to $2" 
    if [[ $mock == 0 ]]; then 
        cp "$1" "$2" 
    fi
}

countbytes() {
    num=($( du -sb "$1" ))
    bytes+=${num[0]}
}

if [[ $debug == 1 ]]; then
    logs=$( realpath "$0" )
    logs="${logs%/*}/log.copy"
    touch "$logs" &&  echo "logging start" > "$logs"
fi

print_msg "=Processing top level arguments=" 


for ((i=1; i<$#; i++)); do
    real=($( realpath "${!i}" ))
    # mapfile -d \/ fields <<< $real
    # echo "${fields[@]}" | cat -et
    for item in "${real[@]}"; do 
        if [[ -d "$item" ]]; then 
            print_msg "$item is a directory"
            dir_table["$item"]="$dest"
        elif [[ -f "$item" ]]; then 
            print_msg "$item is a file" 
            file_table["$item"]="$dest"
            countbytes "$item"
        elif [[ -h "$item" ]]; then 
            print_msg "$item is a symbolic link, not copied" 
        fi 
    done
done

print_msg "=Building directories=" 

while [[ ${#dir_table[@]} -ne 0 ]]; do 

    for key in "${!dir_table[@]}"; do 
        dirname="${key##*/}"
        dest="${dir_table[$key]}/$dirname"
        m_mkdir "$dest" 
        for item in "$key"/*; do 
            if [[ -f "$item" ]]; then 
                file_table["$item"]="$dest"
                countbytes "$item"
            elif [[ -d "$item" ]]; then 
                dir_table["$item"]="$dest"
            elif [[ -h "$item" ]]; then
                print_msg "$item is a symbolic link, not copied" 
            fi
        done
        unset dir_table["$key"]
    done
    count+=${#dir_table[@]}
done

print_msg "Creating directories: done" 

print_msg "=Copying files="
total_bytes=$bytes
bytes=0
show_progress $bytes $total_bytes


for key in "${!file_table[@]}"; do 
    filename="${key##*/}" #get filename
    newfile="${file_table[$key]}/$filename"

    if [[ -e "$newfile" ]]; then
        print_msg "$filename already exists at $newfile" 
        verify "$key" "$newfile"
        if [[ $? -ne 0 ]]; then 
            print_msg "$newfile is different than $key" 
        fi
    else
        m_cp "$key" "${file_table[$key]}"
        sync $newfile
    fi
    countbytes "$key"
    show_progress $bytes $total_bytes
    
    file_table["$key"]="$newfile"

done

sync $dest
print_msg "Copying: complete"
tput hpa $( tput cols )
echo -ne "\n"
print_msg "=Verifying copies=" 
bytes=0
show_progress $bytes $total_bytes


for key in "${!file_table[@]}"; do 
    verify "$key" "${file_table[$key]}"
    if [[ $? -ne 0 ]]; then 
        # rm "${file_table[$key]}"
        print_msg "$key did not copy correctly" 
    fi
    countbytes "$key"
    show_progress $bytes $total_bytes
done

print_msg "Verifying: Done"
tput hpa $( tput cols )
echo -ne "\n"
count+=${#file_table[@]}

print_msg "$count items processed" 





