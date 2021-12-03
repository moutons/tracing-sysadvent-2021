# This may have been a bad idea to demo but here goes

```
root@trace1:~# podman pull jjasghar/container_cobol
✔ docker.io/jjasghar/container_cobol:latest
Trying to pull docker.io/jjasghar/container_cobol:latest...
Error: initializing source docker://jjasghar/container_cobol:latest: reading manifest latest in docker.io/jjasghar/container_cobol: manifest unknown: manifest unknown
```

what's up here? oh, tags:

```
root@trace1:~# podman pull jjasghar/container_cobol:v1
✔ docker.io/jjasghar/container_cobol:v1
Trying to pull docker.io/jjasghar/container_cobol:v1...
Getting image source signatures
Copying blob 22dbe790f715 done
Copying blob dd9f9ef1561e done
Copying blob 071f69fcf3d9 done
Copying blob 89cc79f84665 done
Copying blob f1159f5cff39 done
Copying config a205b963de done
Writing manifest to image destination
Storing signatures
a205b963deaa1d471e6217f439e02ecea6be2a2250de9ed1ebfb7dec72e55d6a
root@trace1:~# strace -ff --trace=%file -o /root/container_cobol podman run -it container_cobol
Hello world!
root@bpftrace1:~# ls -1 container_cobol.* | wc -l
146
root@bpftrace1:~#
```

what have I signed myself up for :o
