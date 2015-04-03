#!/usr/bin/perl
use IPC::Run qw(start harness finish new_chunker run timeout);
my @commit_cmd = ("bash", "-c", "while true; do cat commits; done");
my @vm_cmd = ("inotifywait", "-m", "control/");

my $commits = "";
my $vms = "";
my $commit_h = harness(\@commit_cmd, '>', new_chunker, \&commit_handler);
my $vm_h = harness(\@vm_cmd, '>', new_chunker, \&vm_handler);

my %repos;
my @vms;
my @commits;

sub commit_handler {
    my ($line) = @_;

    warn "line $line";

    chomp $line;

    warn "line $line";

    return if $line =~ /[^-a-zA-Z0-9_ ]/;

    warn "line $line";

    my ($repo, $branch, $revision) = split ' ', $line;

    warn "line $line repo $repo branch $branch revision $revision";

    $repos{$repo}{$branch} = $revision;

    warn "branch $branch of repo $repo now at $revision";

    push @commits, [$repo, $branch]; # but not $revision
}

sub vm_handler {
    my ($line) = @_;

    warn "line $line";

    chomp $line;

    warn "line $line";

    return if $line =~ /[^-\/a-zA-Z0-9_ ]/;

    warn "line $line";

    if ($line =~ /^control\/ CREATE (sivtar-[0-9a-f]*)$/) {
	my ($vm) = $1;

	push @vms, $vm;
    }
}

sub get_vm {
    while (1) {
	while (!@vms) {
	    warn "no vms...";
	    $commit_h->pump_nb;
	    $vm_h->pump;
	    $commit_h->pump_nb;
	}

	while (@vms) {
	    my $vm = pop @vms;
	    my $err;

	    warn "trying vm $vm";
	    if (run(["rm", "-f", "control/$vm"], '2>', \$err)) {
		warn "picked vm $vm";

		return $vm;
	    }
	}
    }
}

sub get_commit {
    while (1) {
	while (!@commits) {
	    $commit_h->pump;
	}

	while (@commits) {
	    my $commit = pop @commits;
	    my ($repo, $branch) = @$commit;

	    next unless exists $repos{$repo}{$branch};
	    my $revision = delete $repos{$repo}{$branch};

	    return [$repo, $branch, $revision];
	}
    }
}

sub launch_sivtar {
    if (fork()) {
	return;
    }

    my ($vm, $repo, $branch, $revision) = @_;

    my $script = <<"EOF";
(git clone --branch "$revision" /mnt/git/"$repo" &&
cd "$repo" &&
if [ -f .sivtar.sh ]; then bash .sivtar.sh; else echo "No sivtar script" > /dev/stderr; true; fi &&
rm -rf "$repo"
)2>&1 |sudo tee /dev/tty1
EOF

    my @ssh_cmd = ("ssh", "-o", "StrictHostKeyChecking=no", "-l", "test", "$vm");
    run(\@ssh_cmd, '<', \$script);

    $script = <<"EOF";
(sleep 2; sudo halt -d -p -f)</dev/null >/dev/null 2>/dev/null &
disown
exit
EOF
    my $h = run(\@ssh_cmd, '<', \$script);
}

while(1) {
    my $vm = get_vm;
    my $commit = get_commit;

    launch_sivtar($vm, @$commit);
}
