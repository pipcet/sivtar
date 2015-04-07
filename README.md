A Travis clone. Use Travis instead.

What you need:
 - a Debian system
  - a web server serving cgi scripts from /srv/http
  - an nfs server serving file systems from /srv/nfs
  - dnsmasq
  - qemu

On the NFS server:
 - install the server/ files to your server
 - export /srv/http as a CGI directory via a web server
 - build a guest file system with bin/build-guest-multistrap
 - copy the guest file system to /srv/nfs/sivtar
 - link /srv/nfs/git to a directory of git repositories for sivtar to use
 - link /srv/nfs/cpan to a CPAN mirror directory for sivtar to use
 - export /srv/nfs/* to the guest machine
 - restart dnsmasq
 - configure sivtar-server as an (additional) host name by adding it to /etc/hosts
 - create a sivtar control directory
 - run sivtar.pl

On the development box:
 - install the devel/ files to your development box
 - link the post-commit git hook to the .git/hooks/ directory of git archives you want to enable sivtar for.
 - commit a change to see what happens

On the host box:
 - configure sivtar-server as a host name for your Sivtar server
 - 