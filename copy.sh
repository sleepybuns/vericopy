#!/bin/bash

debug=1 # debug mode records logs
mock=0 # mock mode does not do any file operations 
bar_size=$(( $(tput cols) -  10 ))
bar_char_done="|"
bar_char_todo="-"
bar_percentage_scale=2

logs="/dev/null"
dest=""
declare -A dir_table
declare -A file_table
declare -A bad_copies
declare -A diff_copies
declare -i bytes=0
declare -i item_count=0
declare -i copy_bytes=1 #prevent divide by zero 
declare -i verify_bytes
declare -i diff=0
declare -i total_cols=0
# declare -i prev_msg_height=0
declare -i next_msg_height=0
declare -i total_rows=0
declare -i curr_row=0
declare -i boundary=0

print_msg() {
    msg=$1
    total_cols=$( tput cols )
    next_msg_height=$(( ${#msg} / $total_cols ))

    tput hpa 0 
    
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
    echo -e "$msg" | tee >(cat >&1) >>$logs
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

# $1: file name 
# $2: variable name, literal (no $) 
# $3: operation +,- etc. 
countbytes() {
    num=($( du -sb "$1" ))
    eval "$2=$(( $2 $3 ${num[0]} ))"
    # bytes+=${num[0]}
}

if [[ $debug == 1 ]]; then
    logs=$( realpath "$0" )
    logs="${logs%/*}/log.copy"
    touch "$logs" &&  echo "logging start" > "$logs"
fi

if [[ -d "${!#}" ]]; then 
    dest=$( realpath "${!#}" )
else 
    print_msg "${!#} is not a directory. Goodbye."
    exit 
fi
    
print_msg "=Processing top level arguments=" 

for ((i=1; i<$#; i++)); do
    item=($( realpath "${!i}" ))
    # mapfile -d \/ fields <<< $real
    # echo "${fields[@]}" | cat -et
    # for item in "${real[@]}"; do 
    if [[ -d "$item" ]]; then 
        print_msg "$item is a directory"
        dir_table["$item"]="$dest"
    elif [[ -f "$item" ]]; then 
        print_msg "$item is a file" 
        file_table["$item"]="$dest"
        countbytes "$item" copy_bytes +
    elif [[ -h "$item" ]]; then 
        print_msg "$item is a symbolic link, not copied" 
    else 
        print_msg "$item is neither file nor directory, skipped" 
    fi 
    item_count+=1
    # done
done

print_msg "=Building directories=" 

while [[ ${#dir_table[@]} -ne 0 ]]; do 

    for key in "${!dir_table[@]}"; do 
        dirname="${key##*/}"
        dirname="${dir_table[$key]}/$dirname"
        m_mkdir "$dirname" 
        for item in "$key"/{,.}*; do 
            if [[ -f "$item" ]]; then 
                file_table["$item"]="$dirname"
                countbytes "$item" copy_bytes +
            elif [[ -d "$item" ]]; then 
                dir_table["$item"]="$dirname"
            elif [[ -h "$item" ]]; then
                print_msg "$item is a symbolic link, not copied" 
            fi
        done
        unset dir_table["$key"]
    done
    item_count+=${#dir_table[@]}
done

print_msg "Creating directories: done" 
item_count+=${#file_table[@]}


print_msg "=Copying files="
verify_bytes=$copy_bytes
bytes=0
show_progress $bytes $copy_bytes


for key in "${!file_table[@]}"; do 
    filename="${key##*/}" #get filename
    newfile="${file_table[$key]}/$filename"

    if [[ -e "$newfile" ]]; then
        print_msg "$filename already exists at $newfile" 
        verify "$key" "$newfile"
        if [[ $? -ne 0 ]]; then 
            print_msg "$newfile is different than $key"
            diff_copies["$newfile"]="$key" 
        fi
        unset file_table["$key"]
        countbytes "$key" verify_bytes -
    else
        m_cp "$key" "${file_table[$key]}"
        file_table["$key"]="$newfile"
    fi
    countbytes "$key" bytes +
    show_progress $bytes $copy_bytes

done

sync "$dest"
bytes+=1
show_progress $bytes $copy_bytes
print_msg "Copying: complete"
tput hpa $( tput cols )
echo -ne "\n"
print_msg "=Verifying copies=" 
bytes=0
show_progress $bytes $verify_bytes


for key in "${!file_table[@]}"; do 
    verify "$key" "${file_table[$key]}"
    if [[ $? -ne 0 ]]; then 
        # rm "${file_table[$key]}"
        print_msg "$key did not copy correctly" 
        bad_copies["$key"]=${file_table[$key]}
    fi
    countbytes "$key" bytes +
    show_progress $bytes $verify_bytes
done

bytes+=1
show_progress $bytes $verify_bytes
print_msg "Verifying: Done"
tput hpa $( tput cols )
echo -ne "\n"

print_msg "$item_count items processed" 

for key in "${!bad_copies[@]}"; do 
    print_msg "$key did not copy correctly to ${bad_copies[$key]}"
done 

for key in "${!diff_copies[@]}"; do 
    print_msg "$key already exists and is different from ${diff_copies[$key]}"
done 




