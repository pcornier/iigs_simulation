


generate the rom files:
```
cd roms
#download  apple2gs.zip from mame froms
make 
```

```
make
./obj_dir/Vtop -t 15 -l 2 -s 20
gtkwave conf.gtkw
```

options are:

-s \<cycle> stop simulation after the number of cycles

-t \<cycle> start tracing at

-l \<length in cycle> wave dump length

