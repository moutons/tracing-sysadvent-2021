# Least Privilege with Process Access Auditing

Security in software development has been a hot-button issue for years. Increasing awareness of the threat posed by supply chain breaches have only increased the pressure on teams to improve security in all aspects of the software delivery and operation. A key premise is least privilege: granting the minimum privileges necessary to accomplish a task, in order to prevent folks from accessing or altering things they shouldn't have rights to. Here's my thinking, we should design tools whether they are a subcommand or a separate utility that apply least privilege. I would like to share my adventure of looking at an InSpec profile (using CINC Auditor) and a container I found on Docker Hub to demonstrate how to apply least privilege using process access auditing.

At my prior job working at Chef, I fielded a request asking how to run an InSpec profile as a user other than root. InSpec allows you to write policies in code (called InSpec Profiles) to audit the state of a system. Most of the documentation and practice at the time had users running InSpec as root or a root-equivalent user. At first glance, this makes a certain amount of sense: InSpec (like many other tools in the "let's configure the entire system" and "let's audit the security of the entire system" spaces) needs access to whatever the user decides they want to check against. Users can write arbitrary profile code for InSpec (and now the open source CINC Auditor), ship those profiles around, and scan their systems to determine whether or not they're in compliance.

I've experienced this pain of excessive privileges with utilities myself. I can't count the number of times we'd get a request to install some vendor tool nobody had ever heard of with root privileges. Nobody who asked could tell us what it'd be accessing, whether it would be able to make changes to the system, or how much network/cpu/disk it'd consume. The vendor and the security department or DBAs or whoever would file a request with the expectation that we should just trust their assertion that nothing would go wrong. So, being responsible system administrators, we'd say "no, absolutely not, tell us what it's going to be doing first" or "yes, we'll get that work scheduled" and then never schedule the work. This put us in the position of being poor actors in the system, and while justified it never sat right with me.

(Note: It is deeply strange that vendors often can't tell customers what their tools do when asked in good faith, as is the idea that there should be an assumption of trustworthiness in that lack of information.)

I've found some tools over the years which might be able to give a user output which can be used to help craft something like a set of required privileges to run an arbitrary program with non-root privileges. Not too long ago I discussed "securing the supply chain" on how to design an ingestion pipeline to enable folks to run containers in a secure environment where they could be somewhat assured that a container using code they didn't write wasn't going to try to access things that they weren't comfortable with. I thought about this old desire of limiting privileges when running an arbitrary command, and figured that I should do a little digging to see if something already existed. If not maybe I could work towards a solution.

Now, I don't consider myself an expert developer but I have been writing or debugging code in one form or another since the '90s. I hope you consider this demo code with the expectation that someone wanting to do this in a production environment will re-implement what I've done far more elegantly. I hope that seeing my thinking and the work will help folks to understand a bit more about what's going on behind the scenes when you run arbitrary code, and to help you design better methods of securing your environment using that knowledge.

What I'll be showing here is the use of strace and some of the tools built on eBPF to build a picture of what is going on when you run code and how to approach crafting a baseline of expected system behavior using the information you can gather. I'll show two examples:

* executing a relatively simple InSpec profile using the open source distribution's CINC Auditor, and 
* running a randomly selected container off Docker Hub (jjasghar/container_cobol).

Hopefully, seeing this work will help you solve a problem in your environment or avoid some compliance pain.

## Parsing strace Output for an CINC Auditor (Chef InSpec) profile

There are other write-ups of strace functionality which go into broader and deeper detail on what's possible using it, [I'll point to Julia Evans' work](https://jvns.ca/categories/strace/) to get you started if you want to know more.

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

## Parsing strace output of a container execut

I said Docker earlier, but I've got podman installed on this machine so that's what the output will reflect. You can find the output of the following command in the `strace-output` [directory](/strace-output/) in files matching the pattern `container_cobol.*`, and wow. Turns out running a full CentOS container produces a lot of output. When scanning through the files, you see what looks like podman doing podman things, and what looks like the COBOL Hello World application executing in the container. As I go through these files I will call out anything particularly interesting I see along the way:

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

So the full CentOS container running a little COBOL Hello World application needs access to six hundred thirty seven files, and CINC Auditor/InSpec running a 22-line profile directly on the OS needs to access over one hundred four thousand files. That doesn't directly mean that one is more or less of a security risk than the other, particularly given that a Hello World application can't report on the compliance state of your machines, containers, or applications for example, but it is fun to think about. One of the neatest things about debugging using tools which expose the underlying operations of a container exec is that you can reason about what containerization is actually doing. In this case, since we're showing what files are accessed during the container exec, sorting the list, and removing duplicate entries it's a cursory view but still useful.

Let's say we're consuming a vendor application as a container. We can trace an execution (or sample a running instance of the container for a day, strace can attach to running processes), load the list of files into the pipeline we use to promote new versions of that vendor app to prod, and when we see a change in the files that the application is opening we can make a determination whether the behavior of the new version is appropriate for our production environment with all the PII and user financial data. Now, instead of trusting the vendor at their word that they've done their due diligence, we're actually observing the behavior of the application and using our own knowledge of our environment to say whether that application is suitable for use.

## But wait! Strace isn't just for files!

I used strace's `file` syscall filter as an example because it fit the example use case, but strace can snoop on other syscalls too! Do you need to know what IP addresses your process knows about? This example is using a container exec again, but you could snoop on an existing pid if you want then run a similar search against the output (IPs have been modified in this output):

```
strace -ff --trace=%network -o /root/yourcontainer-network -s 10241 podman run -it yourcontainer
for file in $(ls -1 yourcontainer-network.*); do grep -oP 'inet_addr\("\K[^"]+' $file ; done
127.0.0.1
127.0.0.1
693.18.119.36
693.18.119.36
693.18.131.255
75.5117.0.5
75.5117.0.5
75.5117.255.255
161.888.0.2
161.888.0.2
161.888.15.255
832.71.40.1
832.71.40.1
832.71.255.255
```

## Strace closing thoughts

With all that knowledge, can we address the original question: Can one use the list of files output by InSpec to provide a restricted set of permissions which will allow one to audit the system using CINC Auditor and the profile with a standard user?

Yes, with one caveat: My Very Simple Profile was too simple, and didn't require any additional privileges. I tried with a few other public profiles, but every one I tried ran successfully using a standard user created with `useradd -m cincauditor`. I looked through bug reports related to running profiles as a non-root user but couldn't replicate their issues - which is good, I suppose. It could be that the issue my customer was facing at the time was a bug in the program's behavior when run as a non-root user which has been fixed, or I just don't remember the use case they presented well enough to replicate it. So here's a manufactured case:

```
root@trace1:~# mkdir /tmp/foo
root@trace1:~# touch /tmp/foo/sixhundred
root@trace1:~# touch /tmp/foo/sevenhundred
root@trace1:~# chmod 700 /tmp/foo
root@trace1:~# chmod 600 /tmp/foo/sixhundred
root@trace1:~# chmod 700 /tmp/foo/sevenhundred
cincauditor@trace1:~$ cat << EOF > linux-vsp/controls/filetest.rb
> control "filetester" do
>   impact 1.0
>   title "Testing files"
>   desc "Ensure they're owned by root"
>   describe file('/tmp/foo/sixhundred') do
>     its('owner') { should eq 'root' }
>   end
>   describe file('/tmp/foo/sevenhundred') do
>     its('group') { should eq 'root'}
>   end
> end
> EOF
cincauditor@trace1:~$ cinc-auditor exec linux-vsp/

Profile: Very Simple Profile (linux-vsp)
Version: 0.1.0
Target:  local://

  ×  filetester: Testing files (2 failed)
     ×  File /tmp/foo/sixhundred owner is expected to eq "root"

     expected: "root"
          got: nil

     (compared using ==)

     ×  File /tmp/foo/sevenhundred group is expected to eq "root"

     expected: "root"
          got: nil

     (compared using ==)

  ✔  inetd: Do not install inetd
     ✔  System Package inetd is expected not to be installed
  ↺  auditd: Check auditd configuration (1 skipped)
     ✔  System Package auditd is expected to be installed
     ↺  Can't find file: /etc/audit/auditd.conf


Profile Summary: 1 successful control, 1 control failure, 1 control skipped
Test Summary: 2 successful, 2 failures, 1 skipped

cincauditor@trace1:~$ find . -name "linux-vsp.1*" -exec awk -F '"' '{print $2}' {} \; | sort -u > linux-vsp_files-accessed.txt

root@trace1:~# diff --suppress-common-lines -y linux-vsp_files-accessed.txt /home/cincauditor/linux-vsp_files-accessed.txt | grep -v /opt/cinc-auditor
							      >	/home
							      >	/home/cincauditor
							      >	/home/cincauditor/.dpkg.cfg
							      >	/home/cincauditor/.gem/ruby/2.7.0
							      >	/home/cincauditor/.gem/ruby/2.7.0/specifications
							      >	/home/cincauditor/.inspec
							      >	/home/cincauditor/.inspec/cache
							      >	/home/cincauditor/.inspec/config.json
							      >	/home/cincauditor/.inspec/gems/2.7.0/specifications
							      >	/home/cincauditor/.inspec/plugins
							      >	/home/cincauditor/.inspec/plugins.json
							      >	/home/cincauditor/linux-vsp
/root							      <
/root/.dpkg.cfg						      <
/root/.gem/ruby/2.7.0					      <
/root/.gem/ruby/2.7.0/specifications			      <
/root/.inspec						      <
/root/.inspec/cache					      <
/root/.inspec/config.json				      <
/root/.inspec/gems/2.7.0/specifications			      <
/root/.inspec/plugins					      <
/root/.inspec/plugins.json				      <
/root/linux-vsp						      <
							      >	/tmp/foo/sevenhundred
							      >	/tmp/foo/sixhundred
							      >	linux-vsp/controls/filetest.rb
root@trace1:~#
```

The end of that previous block's output shows compiling the list of files accessed when the `cincauditor` user runs the profile in the same way we did for the `root` user, then a diff of the two files. Looking at that output, it's fairly obvious that the profile is trying to access the newly created files which are in a directory we made inaccessible to the `cincauditor` user (with `chmod 700 /tmp/foo`), and when we give cinc-auditor access to that directory with `chmod 750 /tmp/foo` the profile is able to check those files. A manufactured replication of the use case, but it does show that it's possible to use the output to accomplish the task. Whether chmod is the right way to give an least-privilege user access to the files is a question best left up to the implementor, their organization, and their auditors - the purpose of this exercise is to demonstrate the potential value of the strace debugger. 

## Parsing ebpftrace Output

[Julia Evans](https://jvns.ca/) has [written](https://jvns.ca/blog/2018/02/05/rust-bcc/) [about](https://jvns.ca/blog/2017/04/07/xdp-bpf-tutorial/) [eBPF](https://jvns.ca/blog/2017/06/28/notes-on-bpf---ebpf/) too, and you should read those posts in addition to [Brendan Gregg's posts on eBPF](https://www.brendangregg.com/ebpf.html) to build your own understanding about this very complex set of tooling.

Prior to considering it for this article, I'd heard of eBPF in platform observability contexts but hadn't dug into it much. With regard to single-process-and-child tracing I have not yet built a functional implementation. However, when considering the ability to build a baseline picture of system behavior and being able to surface potential issues, the performance impact of eBPF tooling is preferable to `strace` and its kin.

## Closing thoughts

Over the past few years I've had a lot of thoughts about how do get things done, and I've come to the conclusion that it's okay to write shell scripts to get something like this done. All I'm doing is wrapping arbitrary tasks so I can extract information about what happens when they're running, and since I won't be able to predict where I'll need it I figured it was totally alright to use bash and awk since it's quite likely those will be available where I want to do this sort of thing.

You might not agree, and wish to see something like this implemented in Ruby or Python or Rust (I have to admit that I thought about trying to do this using Rust so as to get better at it), and you're of course welcome to do so. Again, I chose shell since it's something many folks can easily run, look at, comprehend, modify, and re-implement in the way that suits them.

Lastly, thanks very much to Julia Evans. A note about the power of storytelling in one of her posts made me think "I should write a story about solving this problem so I can be sure I learned something from it", and I think much of the technical documentation I read could be improved if written with the mindset she brings to her writing.
