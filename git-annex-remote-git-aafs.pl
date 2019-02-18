#!/usr/bin/perl
# -*- mode: cperl; cperl-indent-level: 4 -*-
# $ git-annex-remote-git-aafs $
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#	Copyright (c) 2018 Tomi Ollila
#	    All rights reserved
#
# Created: Mon 17 Dec 2018 22:46:31 EET too
# Last modified: Mon 18 Feb 2019 19:18:33 +0200 too

# SPDX-License-Identifier: GPL-3.0-only

# git annex remote git annex addressable file storage (git-aafs)
# - stores files to git repo every file in its own ref (w/o parents)
#
# https://git-annex.branchable.com/special_remotes/external/
# https://git-annex.branchable.com/design/external_special_remote_protocol/

use 5.8.1;
use strict;
use warnings;

use File::Temp;

$| = 1; # output autoflush

$, = ' ';  # output field separator
$\ = "\n"; # output record separator

print 'VERSION', 1;

delete $ENV{GIT_DIR};
delete $ENV{GIT_WORK_TREE};
$ENV{GIT_PAGER} = 'cat';

$ENV{GIT_AUTHOR_NAME} = $ENV{GIT_COMMITTER_NAME} = 'git-annex addressable file';
$ENV{GIT_AUTHOR_EMAIL} = $ENV{GIT_COMMITTER_EMAIL} = 'git-aafs@not.an.example';

#END { warn "$$: --- EXIT $? ---\n" }

sub xxsystem(@) # system w/ stdout redirected to stderr and exit if/unless...
{
    #warn "$$: xxsystem @_\n";
    my $pid = fork;
    die "fork failed!\n" unless defined $pid;
    if ($pid) {
	#alarm 600;
	sleep 1 while (waitpid ($pid, 0) != $pid); # slow loop if ever...
	#alarm 0;
	return $? if defined wantarray;
	die "@_ failed returncode $?\n" if $?;
	return;
    }
    # child
    open(STDOUT, ">&STDERR") or die "Can't dup STDERR to STDOUT: $!\n";
    #system 'printenv';
    exec @_;
    die "exec @_ failed: $!\n";
}

sub xxqx(@) # like qx//, but with list as a command + args, and chomp (and die)
{
    #warn "$$: xxqx @_\n";
    open P, '-|', @_ or die "pipe open: $!\n"; # unlikely
    #alarm 600;
    my $r; {
	local $/; # local slurp mode
	$r = <P>;
    }
    #alarm 0;
    chomp $r; # for the usual case we get one line
    close P;
    #warn "$$: xxqx ($?) $r\n";
    if ($?) {
	return ($r, $?) if wantarray;
	die "@_ failed returncode $?\n";
    }
    return $r;
}

# set by PREPARE
my $aafs_repository;

my %REFS;
sub fetch_refs()
{
    open P, '-|', qw/git ls-remote --refs -h/, $aafs_repository or die $!;
    %REFS = ();
    while (<P>) {
	my ($cid, $ref, @rest) = split;
	$ref =~ s/refs.heads.//;
	$REFS{$ref} = $cid;
    }
    close P or return -1;
    return scalar %REFS;
}

my $cmd;
sub reply_success(@) { print "$cmd-SUCCESS @_" }
sub reply_failure(@) { print "$cmd-FAILURE @_" }

while (<STDIN>) {
    #warn "$$: COMMAND LINE: $_";
    my @l = split /[ \n]/; # 2 spaces, 2 params... -- due to \n we lose trail sp
    $cmd = shift @l;

    if ($cmd eq 'CHECKPRESENT') {
	if (defined $REFS{$l[0]}) {
	    reply_success $l[0];
	    next
	}
	if (fetch_refs < 0) {
	    print "$cmd-UNKNOWN", $l[0], "fetching refs from remote failed";
	    next
	}
	if (defined $REFS{$l[0]}) {
	    reply_success $l[0];
	} else {
	    reply_failure $l[0];
	}
	next
    }
    if ($cmd eq 'TRANSFER') {
	if ($l[0] eq 'STORE') {
	    shift @l; my $key = shift @l;
	    if (defined $REFS{$key}) {
		reply_success 'STORE', $key;
		next
	    }
	    my $file = "@l"; # losing trailing sp (if any) strip'd (do we care?)
	    my $dh = File::Temp->newdir('aafs-wipd.XXXXXX');
	    my @git = ( 'git', '--git-dir', $dh->dirname );
	    xxsystem @git, qw/init --bare/;
	    my $bh = xxqx @git, qw/hash-object -w/, $file;
	    xxsystem @git, qw/update-index --add --cacheinfo 100644/, $bh, $key;
	    my $tree = xxqx @git, 'write-tree';
	    my $commit = xxqx @git, qw/commit-tree -m ./, $tree;
	    if (xxsystem @git, 'push',
		$aafs_repository, "$commit:refs/heads/$key") {
		reply_failure 'STORE', $key, "push to $aafs_repository failed";
		next
	    }
	    $REFS{$key} = $commit;
	    reply_success 'STORE', $key;
	    next
	}
	if ($l[0] eq 'RETRIEVE') {
	    shift @l; my $key = shift @l; my $file = "@l"; # ditto, trail sp ^^^
	    my $dh = File::Temp->newdir('aafs-wipd.XXXXXX');
	    my $tempdir = $dh->dirname;
	    if (xxsystem qw/git clone --depth=1 --single-branch --branch/, $key,
		$aafs_repository, "$tempdir/git") {
		reply_failure 'RETRIEVE', $key, "fetch failed (no content?)";
		next
	    }
	    my $blob = "$tempdir/git/$key";
	    unless (-f $blob) {
		reply_failure 'RETRIEVE', $key, "cannot find $file";
		next
	    }
	    unless (rename $blob, $file) {
		reply_failure 'RETRIEVE', $key, "cannot move $file";
		next
	    }
	    reply_success 'RETRIEVE', $key;
	    next
	}
	# here if not 'STORE' nor 'RETRIEVE'
	reply_failure @l;
	next
    }
    if ($cmd eq 'REMOVE') {
	my $key = $l[0];
	if (xxsystem qw/git push/, $aafs_repository, ":refs/heads/$key") {
	    warn "git push returned nonzero. ignored\n";
	}
	delete $REFS{$key};
	reply_success $key;
	next
    }
    if ($cmd eq 'PREPARE') {
	print 'GETCONFIG repo';
	$_ = <STDIN>;
	$aafs_repository = substr $_, 6, -1;
	unless ($aafs_repository =~ /[:\/]/) {
	    reply_failure "configuration broken: 'repo' value",$aafs_repository;
	} else {
	    reply_success;
	}
	next
    }
    if ($cmd eq 'INITREMOTE') {
	print 'GETCONFIG repo';
	$_ = <STDIN>;
	$_ = substr $_, 6, -1;
	if (/^\s*$/) {
	    reply_failure "$0 expects 'repo=value' to be given in",
	      "`git-annex initremote` parameters";
	    next
	}
	my $r = $_;
	my $ap;
	unless (s/^:// or /^[^\/]+:/)
	{
	    # git-submodule--helper resolve-relative-url (available 2016-04)
	    # ... so we use alternative (perhaps differently buggy) impl.
	    #$aafs_repository =
	    #  xxqx qw/git submodule--helper resolve-relative-url/, $_;
	    # get_default_remote
	    my ($ru, $rv) = xxqx qw/git symbolic-ref -q HEAD/;
	    $ru =~ s,refs/heads/(.*),$1,; # note: not sanitized (trust user)
	    ($ru, $rv) = xxqx qw/git config --get/, "branch.$ru.remote";
	    if ($ru =~ /^\s*$/) {
		$ru = 'origin';
	    } else {
		chomp $ru;
	    }
	    # default remote url
	    ($_, $rv) = xxqx qw/git config --get/, "remote.$ru.url";
	    if ($rv) {
		reply_failure "cannot find url of remote '$ru'";
		next
	    }
	    chomp;
	    if ($r =~ /^\//) { # leading / -- absolute...
		$ap = $r;
	    }
	    elsif ($r !~ /[:\/]/ and $r ne '.' and $r ne '..')
	    {      # no /'s (nor :'s) (nor .|..) -- suffix 'repo' to url
		s/\/+$//;
		my $x = (s/[.]git$// and $r !~ /[.]git$/)? '.git': '';
		$_ = $_ . $r . $x;
	    } else {
		$_ = $_ . '/' . $r;
	    }
	}
	# since no resolve-relative-url used we canonicalize everything here...
	my $pfx = s,^([^/]+:(?://+[^/]+|)),,? $1: '';
	$_ = $ap if defined $ap;
	require File::Spec;
	$_ = File::Spec->canonpath($_) . '/'; $_ = '/' if $_ eq '//';
	1 while (s, (^|/)
		    (?:[^/] | [^./][^/] | [^/][^./] | [^/][^/][^/]+) /[.][.]/
		  ,$1,x );
	s,(?<=/)[.][.]/,,g if /^\//;
	$_ = './' unless $_;
	$aafs_repository = $pfx . $_;
	$aafs_repository =~ s,.\K/$,, unless $r =~ /\/$/;

	warn "...\n$0: initremote access check with $aafs_repository\n";
	if (fetch_refs < 0) {
	    reply_failure "fetching refs from '$aafs_repository' failed";
	    next
	}
	print 'SETCONFIG repo', $aafs_repository;
	reply_success;
	next
    }
    print 'UNSUPPORTED-REQUEST';
}
#warn "EOF\n";
