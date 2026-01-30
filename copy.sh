#!/bin/bash

debug=1 # debug mode records logs
mock=1 # mock mode does not do any file operations 
bar_size=80
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

print_msg() {
    # if [[ ${#msg} -ge $( tput cols ) ]]; then 
    #     echo ""
    # fi
    tput el1  && tput hpa 0 && tput el
    msg=$1
    echo "$msg" | tee >(cat >&1) >>$logs
    # if [[ ${#msg} -ge $( tput cols ) ]]; then 
    #     echo ""
    # fi
    tput cuu1
    echo -ne "$2" 
}

show_progress() {
    current="$1"
    total="$2"
    percent=$(bc <<< "scale=$bar_percentage_scale; 100 * $current / $total" )
    done=$(bc <<< "scale=0; $bar_size * $percent / 100" )
    todo=$(bc <<< "scale=0; $bar_size - $done" )
    done_sub_bar=$(printf "%${done}s" | tr " " "${bar_char_done}")
    todo_sub_bar=$(printf "%${todo}s" | tr " " "${bar_char_todo}")
    echo -ne "\n[${done_sub_bar}${todo_sub_bar}] ${percent}%"
    tput cuu1
}

verify() {
    print_msg "Verifying: $2" 
    og=($( md5sum "$1" ))
    # echo "${og[@]}"
    if [ $mock = 0 ]; then 
        yg=($( md5sum "$2" ))
        cmp -s <( printf ${og[0]} ) <( printf ${yg[0]} )
    else
        cmp -s <( printf ${og[0]} ) <( printf ${og[0]} )        
    fi
}

m_mkdir() {
    print_msg "Creating directory: $1" 
    if [ $mock = 0 ]; then mkdir "$1"; fi
}

m_cp() {
    print_msg "Copying: $1 to $2" 
    if [ $mock = 0 ]; then cp "$1" "$2"; fi
}

countbytes() {
    num=($( du -sb "$1" ))
    bytes+=${num[0]}
}

if [[ $debug = 1 ]]; then
    logs=$( realpath "$0" )
    logs="${logs%/*}/log.copy"
    touch "$logs" &&  echo "logging start" > "$logs"
fi

print_msg "=Processing top level arguments=" "\n"

for ((i=1; i<$#; i++)); do
    real=($( realpath "${!i}" ))
    # mapfile -d \/ fields <<< $real
    # echo "${fields[@]}" | cat -et
    for item in "${real[@]}"; do 
        if [[ -d "$item" ]]; then 
            print_msg "\r$item is a directory"
            dir_table["$item"]="$dest"
        elif [[ -f "$item" ]]; then 
            print_msg "\r$item is a file"
            file_table["$item"]="$dest"
            countbytes $item
        elif [[ -h "$item" ]]; then 
            print_msg "$item is a symbolic link, not copied" "\n"
        fi 
    done
done

print_msg "=Building directories=" "\n"

while [[ ${#dir_table[@]} -ne 0 ]]; do 

    for key in "${!dir_table[@]}"; do 
        dirname="${key##*/}"
        dest="${dir_table[$key]}/$dirname"
        m_mkdir "$dest" 
        for item in "$key"/*; do 
            if [[ -f "$item" ]]; then 
                file_table["$item"]="$dest"
                countbytes $item
            elif [[ -d "$item" ]]; then 
                dir_table["$item"]="$dest"
            elif [[ -h "$item" ]]; then
                print_msg "$item is a symbolic link, not copied" "\n"
            fi
        done
        unset dir_table["$key"]
    done
    count+=${#dir_table[@]}
done

print_msg "=Copying files=" "\n" 
total_bytes=$bytes
bytes=0
show_progress $bytes $total_bytes

for key in "${!file_table[@]}"; do 
    # echo "copying $key to ${file_table[$key]}"
    filename="${key##*/}" #get filename
    newfile="${file_table[$key]}/$filename"
    if [[ -e "$newfile" ]]; then
        print_msg "$filename already exists at $newfile" "\n"
        verify "$key" "$newfile"
        # original=($( md5sum "$key" ))
        # check=($( md5sum "$newfile" ))
        # cmp -s <( printf ${original[0]} ) <( printf ${check[0]} )
        if [[ $? -ne 0 ]]; then 
            print_msg "$newfile is different than $key" "\n"
        fi
    else
        m_cp "$key" "${file_table[$key]}"
    fi
    countbytes $key
    show_progress $bytes $total_bytes
    
    file_table["$key"]="$newfile"

done
tput hpa 0 && tput cuu1 && tput el
echo -n "=copying complete="
echo -e "\n"
print_msg "=Verifying copies=" "\n"

for key in "${!file_table[@]}"; do 
    # echo "verifying: ${file_table[$key]}"
    verify "$key" "${file_table[$key]}"
    if [[ $? -ne 0 ]]; then 
        # rm "${file_table[$key]}"
        print_msg "$key did not copy correctly" "\n"
    fi
done

count+=${#file_table[@]}

print_msg "$count items processed" "\n"





