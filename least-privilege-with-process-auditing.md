# Least Privilege with Process Access Auditing

TODO: slice and dice all these words. I tend to write almost oppressively verbosely until my own first editing pass, then cut liberally.

In order that folks understand my thinking I will explain how I came to this topic before diving in, because otherwise I feel like this won't make a terrible lot of sense and with this context I feel like this article could provide more benefit.

Security in software development is a current hot topic. A key premise is least privilege, in other words granting the minimum privileges necessary to accomplish a task, in order to prevent folks from accessing or altering things they shouldn't have rights to. Here's my thinking, we should design tools whether they are a subcommand or a separate utility that apply least privilege. I want to share my adventure of looking at an InSpec profile (using CINC Auditor) and a container I found on Docker Hub to show you one method to use least privilege with process access auditing. 

Because there's a difference between what I think myself and what the company I work for determines, I let the user know the official answer, since they were a paying customer: that while it might be possible to use strace to determine what access was required so as to allow a profile to be run as a non-root user, there was no official support for that and that they'd be on their own.

Some months later I got a response to the feature request that what I was requesting was not related to the product's functionality and the issue was closed.

QUESTION: Is this context interesting or relevant? I suspect I should cut it down to maybe 2 paragraphs max.

Here's the thing; I've experienced this pain of excessive privileges with different utilities, for example in 2012 when I was a sysadmin and the security department wanted to run some tool I'd never heard of to do security things on our boxes. We'd get a request to install some vendor tool nobody had ever heard of with root privileges, and nobody could tell us what it'd be accessing, whether it would be able to make changes to the system, or how much network/cpu/disk it'd consume with the expectation that we should just trust that nothing would go wrong. So, being responsible system administrators, we'd say "no, absolutely not, tell us what it's going to be doing first" or "yes, we'll get that work scheduled" and then never schedule the work. (Note: It is weird that vendors can't tell customers what their tools precisely do and that there should be an assumption of trust.)

I've found some tools over the years which might be able to give a user output which can be used to help craft something like a set of required privileges to run an arbitrary program with non-root privileges. Not too long ago I discussed "securing the supply chain" on how to design an ingestion pipeline to enable folks to run containers in a secure environment where they could be somewhat assured that a container using code they didn't write wasn't going to try to access things that they weren't comfortable with. I thought about this old desire of limiting privileges when running an arbitrary command, and figured that I should do a little digging to see if something already existed. If not maybe I could write up a bit of a tool.

Now, I don't consider myself an expert, but I have been writing or debugging code in one form or another since the '90s. I don't have a lot of practice in this millennium and consider this demo code with the expectation that someone wanting to do this in a production environment will re-implement what I've done far more elegantly - I hope that seeing my thinking and the work will help folks to understand a bit more about what's going on behind the scenes when you run arbitrary code, and to help you design better methods of securing your environment using that knowledge.

What I'll be showing here is the use of strace and some of the tools built on eBPF, to build a picture of what is going on when you run code and how to approach crafting a baseline of expected system behavior using the information you can gather. I'll show two examples:

* executing a relatively simple InSpec profile using the open source distribution's CINC Auditor, and 
* running a randomly selected container off Docker Hub (jjasghar/container_cobol).

Hopefully, seeing this work will help you solve a problem in your environment or avoid some compliance pain.

## Parsing strace Output for an CINC Auditor (InSpec) profile

There have been much better write-ups of strace functionality than I will be able to get into here, [I'll point to Julia Evans' work](https://jvns.ca/categories/strace/) to get you started if you need more than what I'll write here.

Strace is the venerable Linux debugger, and a good tool to use when coming up against a "what's going on when this program runs" problem. However, its output can be decidedly unfriendly. Take a look in the [`strace-output` directory in this repo](/strace-output) for the files matching the pattern `linux-baseline.*` to see the output of the following command:

```
root@trace1:~# strace --follow-forks --output-separately --trace=%file -o /root/linux-baseline cinc-auditor exec linux-baseline
```

You can parse the output, however, if all you want to know is what files might need to be accessed ([for an explanation of the command go here](https://explainshell.com/explain?cmd=awk+-F+%27%22%27+%27%7Bprint+%242%7D%27+linux-baseline%2Flinux-baseline.108579+%7C+sort+-uR+%7C+head)) you can do something similar to the following (maybe don't randomly sort the output and only show 10 lines):

```
awk -F '"' '{print $2}' linux-baseline/linux-baseline.108579 | sort -uR | head
/opt/cinc-auditor/embedded/lib/ruby/gems/2.7.0/gems/minitest-5.14.4/lib/nokogiri.so
/opt/cinc-auditor/embedded/lib/ruby/gems/2.7.0/gems/train-winrm-0.2.12/lib/psych/visitors.rb
/opt/cinc-auditor/embedded/lib/ruby/gems/2.7.0/gems/i18n-1.8.10/lib/rubygems/resolver/index_set.rb
/opt/cinc-auditor/embedded/lib/ruby/gems/2.7.0/gems/aws-sdk-cognitoidentityprovider-1.53.0/lib/inspec/resources/command.rb
/opt/cinc-auditor/embedded/lib/ruby/gems/2.7.0/gems/jwt-2.3.0/lib/rubygems/package/tar_writer.rb
/opt/cinc-auditor/embedded/lib/ruby/gems/2.7.0/gems/aws-sdk-codecommit-1.46.0/lib/pp.rb
/opt/cinc-auditor/embedded/lib/ruby/gems/2.7.0/extensions/x86_64-linux/2.7.0/ffi-1.15.4/http/2.rb
/opt/cinc-auditor/embedded/lib/ruby/gems/2.7.0/extensions/x86_64-linux/2.7.0/bcrypt_pbkdf-1.1.0/rubygems/package.rb
/opt/cinc-auditor/embedded/lib/ruby/gems/2.7.0/gems/aws-sdk-databasemigrationservice-1.53.0/lib/inspec/resources/be_directory.rb
/opt/cinc-auditor/embedded/lib/ruby/gems/2.7.0/gems/aws-sdk-ram-1.26.0/lib/rubygems/resolver/current_set.rb
```

You can start to build a picture of what all the user would need to be able to access in order to run a profile based on that output, but in order to go further I'll use a [much more simple check](/linux-vsp/):

```
cinc-auditor exec linux-vsp/
```

Full results of that command are located in the [`strace-output` directory](/strace-output/) with files matching the pattern `linux-vsp.*`, but to summarize  what cinc-auditor/inspec is doing:

* [linux-vsp.109613](/strace-output/linux-vsp.109613) - this file shows all the omnibussed ruby files the `cinc-auditor` command tries to access in order to run its parent process
* [linux-vsp.109614](/strace-output/linux-vsp.109614) - why auditor is trying to run `cmd.exe` on a Linux system I don't yet know, you'll get used to seeing $PATH traversal very quickly
* [linux-vsp.109615](/strace-output/linux-vsp.109615) - I see a `Get-WmiObject Win32_OperatingSys` in there so we're checking to see if this is Windows
* [linux-vsp.109616](/strace-output/linux-vsp.109616) - more looking on the $PATH for `Get-WmiObject` so more Windows checking
* [linux-vsp.109617](/strace-output/linux-vsp.109617) - I am guessing that checking the $PATH for the `Select` command is more of the same
* [linux-vsp.109618](/strace-output/linux-vsp.109618) - Looking for and not finding `ConvertTo-Json`, this is a PowerShell cmdlet, right?
* [linux-vsp.109619](/strace-output/linux-vsp.109619) - Now we're getting somewhere on Linux, this running `uname -s` (with $PATH traversal info in there, see how used to this you are by now?)
* [linux-vsp.109620](/strace-output/linux-vsp.109620) - Now running `uname -m`
* [linux-vsp.109621](/strace-output/linux-vsp.109621) - Now running `test -f /etc/debian_version`
* [linux-vsp.109622](/strace-output/linux-vsp.109622) - Doing something with `/etc/lsb-release` but I didn't use the `-v` or `-s strsize` flags with strace so the command is truncated.
* [linux-vsp.109623](/strace-output/linux-vsp.109623) - Now we're just doing `cat /etc/lsb-release` using locale settings
* [linux-vsp.109624](/strace-output/linux-vsp.109624) - Checking for the `inetd` package
* [linux-vsp.109625](/strace-output/linux-vsp.109625) - Checking for the `auditd` package, its config directory `/etc/dpkg/dpkg.cfg.d`, and the config files `/etc/dpkg/dpkg.cfg`, and `/root/.dpkg.cfg`

Moving from that to getting an idea of what all a non-root user would need to be able to access, you can do something like this in the strace-output directory ([explainshell here](https://explainshell.com/explain?cmd=find+.+-name+%22linux-vsp.10*%22+-exec+awk+-F+%27%22%27+%27%7Bprint+%242%7D%27+%7B%7D+%5C%3B+%7C+sort+-u+%3E+linux-vsp_files-accessed.txt)):

```
find . -name "linux-vsp.10*" -exec awk -F '"' '{print $2}' {} \; | sort -u > linux-vsp_files-accessed.txt
```

You can see the [output of this command here](/strace-output/linux-vsp_files-accessed.txt), but you'll need to interpret some of the output from the perspective of the program being executed. For example, I see "Gemfile" in there without a preceding path. I expect that's Auditor looking in the `./linux-vsp` directory where the profile being called exists, and the other entries without a preceding path are probably also relative to the command being executed.

## Parsing strace output of a container execution

I said Docker earlier, but I've got podman installed on this machine so that's what the output will reflect. You can find the output of the following command in the `strace-output` directory in files matching the pattern `container_cobol.*`, and wow. Turns out running a full CentOS container produces a lot of output. I scan through the files to see what looks like podman doing podman things, and what looks like the COBOL Hello World application executing in the container, and call out anything particularly interesting I see along the way:

```
root@trace1:~# strace -ff --trace=%file -o /root/container_cobol podman run -it container_cobol
Hello world!
root@trace1:~# ls -1 container_cobol.* | wc -l
146
```

I'm not going to go through 146 files individually as I did previously, but this is an interesting data point:

```
root@trace1:strace-output# find . -name "container_cobol.1*" -exec awk -F '"' '{print $2}' {} \; | sort -u > container_cobol_files-accessed.txt

root@trace1:strace-output# wc -l container_cobol_files-accessed.txt
637 container_cobol_files-accessed.txt

root@trace1:strace-output# wc -l linux-vsp_files-accessed.txt
104754 linux-vsp_files-accessed.txt
```

So the full CentOS container running a little COBOL Hello World application needs access to six hundred thirty seven files, and CINC Auditor/InSpec running a 22-line profile directly on the OS needs to access over one hundred four thousand files. That doesn't directly mean that one is more or less of a security risk than the other, particularly given that a Hello World application can't report on the compliance state of your machines, containers, or applications for example, but it is fun to think about.

TODO: super fun to remember what containers are actually doing via this output, isn't it?

TODO: what can you do with this output in a pipeline

TODO: call out processes which didn't access files - how do you dig into them?

TODO: can one use this to run a profile without root? if not why does it matter?

## Parsing ebpftrace Output

[Julia Evans](https://jvns.ca/) has [written](https://jvns.ca/blog/2018/02/05/rust-bcc/) [about](https://jvns.ca/blog/2017/04/07/xdp-bpf-tutorial/) [eBPF](https://jvns.ca/blog/2017/06/28/notes-on-bpf---ebpf/) too, and you should read those posts in addition to Brendan Gregg's posts.

I've really only been looking at eBPF tooling in my spare time for the past month, I'd heard of it previously in different contexts but hadn't dug into it much so I don't know enough yet about how it could be used to attach to a particular process and follow it along during execution, rather than observe system behavior as a whole across a slice of time to enable system monitoring and performance observation. Still, it can be useful in this context so I'll write about it a bit.

TODO: the rest of this material is on another machine, add it

## Closing thoughts

Over the past few years I've had a lot of thoughts about how do get things done, and I've come to the conclusion that it's okay to write shell scripts to get something like this done. All I'm doing is wrapping arbitrary tasks so I can extract information about what happens when they're running, and since I won't be able to predict where I'll need it I figured it was totally alright to use bash and awk since it's quite likely those will be available where I want to do this sort of thing.

You might not agree, and wish to see something like this implemented in Ruby or Python or Rust (I have to admit that I thought about trying to do this using Rust so as to get better at it), and you're of course welcome to do so. Again, I chose shell since it's something many folks can easily run, look at, comprehend, modify, and re-implement in the way that suits them.

Lastly, thanks very much to Julia Evans, who is an inspirational writer. A note at the bottom of this article made me think "I should write something about solving this problem so I can be sure I learned something from it", and I think much of the technical documentation I read could be improved if written with the mindset she brings to her writing.
