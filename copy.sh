#!/bin/bash

verify_copy() {
    file=$1
    dest=$2
    # cp $file $dest
    # og=($( md5sum "$file" ))
    name=${file##*/}
    echo "copying $file call $name to $dest then verifying"
    # copy=($( md5sum "$dest/$name" ))
    # cmp -s <( printf ${og[0]} ) <( printf ${copy[0]} )
    # if [[ $? != 0 ]]; then 
        # rm "${copy[1]}"
        # echo "$file did not copy correctly"
    # fi
}

dir_copy() {
    src=$1
    dirname=${src##*/}
    dest=$2/$dirname
    echo "copying directory $src called $dirname to $dest"
    # mkdir "$dest"
    for file in $src/*; do 
        echo "dealting with $file in $src, copying to $dest"
        if [[ -d $file ]]; then 
            dir_copy "$file" "$dest"
        else 
            verify_copy "$file" "$dest"
        fi  
    done
}

dest=$( realpath "${!#}")
declare -A dir_table
declare -A file_table

for ((i=1; i<$#; i++)); do
    real=$( realpath "${!i}" )
    # mapfile -d \/ fields <<< $real
    # echo "${fields[@]}" | cat -et
    if [[ -d "$real" ]]; then 
        echo "top level: $real is a directory"
        dir_table["$real"]="$dest"
    elif [[ -f "$real" ]]; then 
        echo "top level: $real is a file"
        file_table["$real"]="$dest"
    elif [[ -h "$real" ]]; then 
        echo "$real is a symbolic link, not copied"
    fi 
done

declare -i count

while [[ ${#dir_table[@]} -ne 0 ]]; do 

    for key in "${!dir_table[@]}"; do 
        dirname="${key##*/}"
        dest="${dir_table[$key]}/$dirname"
        mkdir "$dest" 
	    # echo "making directory $dest"
        for item in "$key"/*; do 
            if [[ -f "$item" ]]; then 
                # echo "$item is a file in $key"
                # echo "$item will be copied to $dest"
                file_table["$item"]="$dest"
            elif [[ -d "$item" ]]; then 
                # echo "$item is a directory in $key"
                # echo "$item will be a directory in $dest"
                dir_table["$item"]="$dest"
            elif [[ -h "$item" ]]; then
                echo "$item is a symbolic link, not copied"
            fi
        done
        unset dir_table["$key"]
    done
    count+=${#dir_table[@]}
done
for key in "${!file_table[@]}"; do 
    # echo "copying $key to ${file_table[$key]}"
    filename="${key##*/}" #get filename
    newfile="${file_table[$key]}/$filename"
    if [[ -e "$newfile" ]]; then
        original=($( md5sum "$key" ))
        check=($( md5sum "$newfile" ))
        cmp -s <( printf ${original[0]} ) <( printf ${check[0]} )
        if [[ $? -ne 0 ]]; then 
            cp "$key" "${file_table[$key]}"
        fi
    else
        cp "$key" "${file_table[$key]}"
    fi
    
    file_table["$key"]="$newfile"

done
for key in "${!file_table[@]}"; do 
    echo "verifying: ${file_table[$key]}"
    og=($( md5sum "$key" ))
    # echo "${og[@]}"
    yg=($( md5sum "${file_table[$key]}" ))
    cmp -s <( printf ${og[0]} ) <( printf ${yg[0]} )
    if [[ $? -ne 0 ]]; then 
        rm "${file_table[$key]}"
        echo "$key did not copy correctly"
    fi
done

count+=${#file_table[@]}

echo "$count items processed"





