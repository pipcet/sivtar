#!/usr/bin/perl
use YAML::XS;
use Data::Dumper;
use IPC::Run qw(start harness finish new_chunker run timeout);
use strict;

my @commit_cmd = ("bash", "-c", "while true; do cat commits; done");
my @vm_cmd = ("inotifywait", "-m", "control/");

my $commits = "";
my $vms = "";
my $commit_h = harness(\@commit_cmd, '>', new_chunker, \&commit_handler);
my $vm_h = harness(\@vm_cmd, '>', new_chunker, \&vm_handler);

my %repos;
my @vms;
my @commits;
my $lastline;

sub commit_handler {
    my ($line) = @_;

    warn "line $line";

    chomp $line;

    warn "line $line";

    return if $line =~ /[^-\/a-zA-Z0-9_ ]/;

    $line = $lastline if $line eq "";
    $lastline = $line;

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

    return if $line =~ /[^-\/a-zA-Z0-9_ :]/;

    warn "line $line";

    if ($line =~ /^control\/ (CREATE|OPEN) ([0-9a-f:]*)$/) {
	my ($vm) = $2;

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
	    if (run(["rm", "-f", "control/$vm"], '2>', \$err) &&
		run(["ping6", "-c", "1", "$vm"])) {
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

sub get_yaml {
    my ($vm, $repo, $branch, $revision) = @_;

    my $yaml_src; my $err;
    my $script = <<"EOF";
(cd /mnt/git/"$repo"; git show "$revision":.sivtar.yml || git show "$revision":.travis.yml)
EOF
    my @ssh_cmd = ("ssh", "-o", "StrictHostKeyChecking=no", "-l", "sivtar", "$vm", "/bin/bash");

    run(\@ssh_cmd, '<', \$script, '>', \$yaml_src, '2>', \$err);

    my $yaml = YAML::XS::Load($yaml_src);

    return $yaml;
}

sub build_scripts {
    my ($vm, $repo, $branch, $revision, $yaml) = @_;
    my $perl_versions = $yaml->{perl} || ["5.20"];
    my $environments = $yaml->{env} || [""];
    my @scripts;

    my $inner = join(" &&\n",
		     @{$yaml->{before_install} || []},
		     @{$yaml->{install} || []},
		     @{$yaml->{script} || []});

    for my $perl_version (@$perl_versions) {
	for my $env (@$environments) {
	    $env = "export $env; " if $env ne "";
	    my $script = <<"EOF";
(git clone --branch "$branch" /mnt/git/"$repo" "$repo" &&
cd "$repo" &&
git checkout "$revision" &&
($env $inner) &&
rm -rf "$repo"
)2>&1 |sudo tee /dev/console
EOF
	    warn $script;
	    push @scripts, $script;
	}
    }

    return @scripts;
}

sub shutdown_vm {
    my ($vm) = @_;
    my @ssh_cmd = ("ssh", "-o", "StrictHostKeyChecking=no", "-l", "sivtar", "$vm", "/bin/bash");

    my $script = <<"EOF";
(sleep 2; sudo halt -d -p -f) </dev/null >/dev/null 2>/dev/null &
disown
exit
EOF
    my $h = run(\@ssh_cmd, '<', \$script);
}

sub launch_sivtar {
    my $fres = fork();

    if ($fres != 0) {
	return;
    } else {
#	$commit_h->finish;
#	$vm_h->finish;
    }

    my ($vm, $repo, $branch, $revision, $script) = @_;

    my @ssh_cmd = ("ssh", "-o", "StrictHostKeyChecking=no", "-l", "sivtar", "$vm", "/bin/bash");
    run(\@ssh_cmd, '<', \$script);

    shutdown_vm($vm);

    exit(0);
}

while(1) {
    my $vm = get_vm;
    my $commit = get_commit;

    my @scripts = build_scripts($vm, @$commit, get_yaml($vm, @$commit));

    shutdown_vm($vm);

    for my $script (@scripts) {
	warn "script: $script";
	launch_sivtar(get_vm, @$commit, $script);
    }
}
