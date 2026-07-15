This is a work in progress platform implementation for unikraft. Anything might be subject to change

## GDB
to connect gdb run:

```bash
make && gdb -q -ex 'set confirm off' -ex 'target extended-remote :3333' -ex 'file build/kernel.elf' -ex 'load' -ex 'tbreak src/start.S:19' -ex 'continue' -ex 'set $x0 = 0' -ex 'break kernel_main'
```

then run in gdb

```gdb
set $x0 = 0 
continue
```


## uart:
observe raspi usart using note the device name may be different on your system, check with `ls /dev/cu.*` and look for something like `cu.usbmodem102` or `cu.usbserial-0001`

```bash
tio /dev/cu.usbmodem102 -b 115200         
```

never use unsafe c functions that could cause buffer overflows, use safer alternatives like `strncpy` or `snprintf` instead. Always validate user input to prevent security vulnerabilities.

## Journal
after every run, if you implemented a feature or changed some code, you must append to the JOURNAL.md file what you did. Append the least amount of information that one would need to reproduce the same results. Do not append if you merely answered questions about the code and did not change any files.


# Parent Repo:
This is a platform implementation to run unikraft on rapberry pi 5. the code for unikraft can be found at ../unikraft look at the unikraft code for reference or when the user asks questions about unikraft.