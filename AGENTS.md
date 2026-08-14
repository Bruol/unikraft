This is a work in progress platform implementation for unikraft. Anything might be subject to change

## GDB
look @README.md to find out how to connect UART & GDB

never use unsafe c functions that could cause buffer overflows, use safer alternatives like `strncpy` or `snprintf` instead. Always validate user input to prevent security vulnerabilities.

## debugging changes
If you want ot debug changes on the raspberry pi, attach to the tmux session running the SemesterProject session. There is a window with gdb and uart connected you can upload new kernel

## Journal
after every run, if you implemented a feature or changed some code, you must append to the JOURNAL.md file what you did. Append the least amount of information that one would need to reproduce the same results. Do not append if you merely answered questions about the code and did not change any files.

## Parent Repo:
This is a platform implementation to run unikraft on rapberry pi 5. the code for unikraft can be found at ../unikraft look at the unikraft code for reference or when the user asks questions about unikraft. You are not alloed to make any changes to the unikraft repo. All changes need to be made in this repo and then merged and link/compile time

## Report
the report is located at ../report. Use /Users/bruol/code/sp/report/sample_text.txt for a style reference for the report.