# vericopy
copying files with MD5 hash verification. 

usage: copy.sh [name ...] destination

name can be either file or directory 
destination is the directory

currently logging is enabled by default, but it's not very well implemented; new logs will erase old logs.

future developments: 
- better logging
- better optimization for HDD to prevent fragmentation
- better error handling


Might rewrite this to turn it into a actual program with a gui
