# Least Privilege with Process Access Auditing

First, thanks very much to Julia Evans, who is an inspirational writer. A note at the bottom of this article made me think "I should write something about solving this problem so I can be sure I learned something from it", and I think much of the technical documentation I read could be improved if written with 

In order that folks understand my thinking I will explain how I came to this topic before diving in, because otherwise I feel like this won't make a terrible lot of sense and with this context I feel like this article could provide more benefit.

I no longer work there, but during the time I was working at Chef I fielded a request from someone who was asking how they could run an InSpec profile as a user other than root. I had a bit of a think about that one, because according to all the examples I'd seen, folks tend to run InSpec as a user with elevated privileges and Chef didn't provide any examples I could find about how to do it otherwise. This makes a certain amount of sense: InSpec (like many other tools in the "let's configure the entire system" and "let's audit the security of the entire system" spaces) needs to be able to interact with whatever the user decides they want to check against. Users can write arbitrary profile code for InSpec (or the open source CINC Auditor), ship those profiles around, and scan their systems to determine whether or not they're in compliance. While questions about the user privileges necessary to run Chef's kit (mostly all of Chef's product documentation at the time was written with the express assumption that many commands and processes must be run as root, in some cases another root-privilege user, or Administrator on Windows) had come up before, in this case I decided I'd heard "No, that's not possible at this time" enough and thought I'd file a feature request. Here was my thinking:

We should design a tool, whether that's a subcommand or a separate utility, which wraps an InSpec run and parses out all the things that run accesses which are likely to be of interest to a corporate security department. Most likely that'd mean checking all the files which are accessed during the run, but could mean snagging network information as well.

Because there's a difference between what I think myself and what the company I work for determines, I let the user know the official answer, since they were a paying customer: that while it might be possible to use strace to determine what access was required so as to allow a profile to be run as a non-root user, there was no official support for that and that they'd be on their own.

Some months later I got a response to the feature request that what I was requesting was not related to the product's functionality and the issue was closed.

I've experienced a similar desire to my customer's before with different utilities, for example in 2012 when I was a sysadmin and the security department wanted to run some tool I'd never heard of to do security things on our boxes. Usually we'd get a request to install some vendor tool nobody'd ever heard of with root privileges, and nobody could tell us what all it'd be accessing, whether it would be able to make changes to the system, or how much network/cpu/disk it'd consume. So, being responsible system administrators, we'd say "no, absolutely not, tell us what it's going to be doing first" or "yes, we'll get that work scheduled" and then never schedule the work. That felt weird to me, that nobody including the vendor could tell us what all their tool would be doing, and I often thought about what could be done to address this.

I've found some tools over the years which might be able to give a user output which can be used to help craft something like a set of required privileges to run an arbitrary program with non-root privileges, but not too long ago I was having a "securing the supply chain" sort of discussion about how to design an ingestion pipeline to enable folks to run containers in a secure environment where we could be somewhat assured that a container using code we didn't write wasn't going to try to access things which we weren't comfortable with. I thought about this old desire, and figured that I should do a little digging to see if something already existed. If not maybe I could write up a bit of a tool.

Now, I should make clear that I am nobody's idea of an expert programmer. I have been writing or debugging code in one form or another since the '90s, but I don't have a lot of practice in this milennium and so I will be sharing my work with every expectation that someone wanting to do this in a production environment will reimplement what I've done far more elegantly - I hope that seeing my thinking and the work will help folks to understand a bit more about what's going on behind the scenes when you run arbitrary code, and to help you design better methods of securing your environment using that knowledge.

What I'll be showing here is the use of strace and some of the tools built on ebpf, to build a picture of what is going on when you run code and how to approach crafting a baseline of expected system behavior using the information you can gather. I'll show two examples:

* executing a relatively simple InSpec profile using CINC Auditor, and 
* running a randomly selected container off Dockerhub (jjasghar/cobol-batch).

Hopefully, seeing this work will help you solve a problem in your environment or avoid some compliance pain.

## Parsing strace Output

There have been much better writeups of strace functionality than I will be able to get into here, [I'll point to Julia Evans' work](https://jvns.ca/categories/strace/) to get you started if you need more than what I'll write here.

Strace is the venerable Linux debugger, and the 

## Parsing ebpftrace Output

Again, [Julia Evans](https://jvns.ca/) has [written](https://jvns.ca/blog/2018/02/05/rust-bcc/) [about](https://jvns.ca/blog/2017/04/07/xdp-bpf-tutorial/) [ebpf](https://jvns.ca/blog/2017/06/28/notes-on-bpf---ebpf/) and you should read those posts as well as Brendan Gregg's posts because it's a lot to wrap your head around. 

I've really only been looking at eBPF tooling in my spare time for the past month, I'd heard of it previously in different contexts but hadn't dug into it much so I don't know enough yet about how it could be used to attach to a particular process and follow it along during execution, rather than observe system behavior as a whole across a slice of time to enable system monitoring and performance observation. Still, it can be useful in this context so I'll write about it a bit.



## Thoughts on utility

Over the past few years I've had a lot of thoughts about how do get things done, and I've come to the conclusion that it's okay to write shell scripts to get something like this done. All I'm doing is wrapping arbitrary tasks so I can extract information about what happens when they're running, and since I won't be able to predict where I'll need it I figured it was totally alright to use bash and awk since it's quite likely those will be available where I want to do this sort of thing.

You might not agree, and wish to see something like this implemented in Ruby or Python or Rust (I have to admit that I thought about trying to do this using Rust so as to get better at it), and you're of course welcome to do so. Again, I chose shell since it's something many folks can easily run, look at, comprehend, modify, and reimplement in the way that suits them.
