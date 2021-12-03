# Yikes, what is going on with this strace command

```
root@trace1:~# strace --follow-forks --output-separately --trace=%file -o /root/linux-baseline cinc-auditor exec linux-baseline
```

for context, this command runs strace with the following flags (excerpted from the strace manpage):

```
       --follow-forks
              Trace child processes as they are created by currently
              traced processes as a result of the fork(2), vfork(2) and
              clone(2) system calls.  Note that -p PID -f will attach
              all threads of process PID if it is multi-threaded, not
              only thread with thread_id = PID.

       --output-separately
              If the --output=filename option is in effect, each
              processes trace is written to filename.pid where pid is
              the numeric process id of each process.

       --trace=syscall_set
              Trace only the specified set of system calls.

              %file  Trace all system calls which take a file name as an
                     argument.  You can think of this as an abbreviation
                     for -e trace=open,stat,chmod,unlink,...  which is
                     useful to seeing what files the process is
                     referencing.  Furthermore, using the abbreviation
                     will ensure that you don't accidentally forget to
                     include a call like lstat(2) in the list.  Betchya
                     woulda forgot that one.
              after each system call.

       --output=filename
              Write the trace output to the file filename rather than to
              stderr.  filename.pid form is used if -ff option is
              supplied.
```

And the command being traced is this, which is executing cinc-auditor against the profile in the `linux-baseline` directory in the current working directory:

```
cinc-auditor exec linux-baseline
```
