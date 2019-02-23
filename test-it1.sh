#!/bin/sh
#
# Created: Wed 19 Dec 2018 22:48:39 EET too
# Last modified: Sat 23 Feb 2019 18:03:06 +0200 too

# SPDX-License-Identifier: BSD-2-Clause

case ${BASH_VERSION-} in *.*) set -o posix; shopt -s xpg_echo; esac
case ${ZSH_VERSION-} in *.*) emulate ksh; esac

set -euf

LANG=C.UTF-8 LC_ALL=C.UTF-8; export LANG LC_ALL; unset LANGUAGE

die () { printf '%s\n' "$*"; exit 1; } >&2

# quick hack, added to test repo setting
repo=:./.;  case ${1-} in repo=*) eval $1; shift; esac

f=unset s= debug=
for arg
do
	case $arg in --fast) f=--fast
		  ;; --fill) f=
		  ;; --debug) debug=--debug
		  ;; [1-9]*) s=--size=$arg
		  ;; *) die "'$arg': unknown option"
	esac
done

if test $f = unset
then
	echo
	echo Usage: $0 '(--fast|--full) [[1-9]*] [--debug]'
	echo
	echo '' --fast runs git-annex testremote with --fast option
	echo '' --full does not
	echo '  [1-9]* sets value to git-annex testremote --size option'
	echo '' --debug is passed to git-annex commands
	echo
	echo '' ./tdir/. will be populated with test environment
	echo
	echo "See $0 and "'`man git-annex-testremote` for more information.'
	echo
	exit 0
fi

test -d tdir && rm -f tdir/latest || mkdir tdir
td=`exec mktemp -d tdir/kXXXXX.git`
ln -s ${td#*/} tdir/latest

test -e tdir/git-annex-remote-git-aafs ||
	ln -s ../git-annex-remote-git-aafs.pl tdir/git-annex-remote-git-aafs

# simulating ssh remotes which are inaccessible (or don't have git-annex-shell)
#test -e tdir/ssh || ln -s /bin/false tdir/ssh
#test -e tdir/ssh || ln -s /bin/true tdir/ssh

set -x
:
PATH=$PWD/tdir:$PATH; export PATH
cd $td
:
git init --template=/dev/null
:
git config user.email 'aafs@example.org'
git config user.name 'git annex addressable file storage test'
:
git config remote.origin.url git@example.org:local/path/to/repo/
#git config remote.origin.annexUrl file:///dev/null
git config remote.origin.annex-ignore true
#git config remote.origin.annex-shell /bin/true
#git config remote.origin.url git@github.com:local/path/to/repo
:
git-annex init 'jepjep'
:
git-annex $debug initremote git-aafs \
	type=external externaltype=git-aafs encryption=none \
	repo=$repo sshcommand=.
:
test $repo = :./. || exit 0

git-annex $debug testremote $f $s git-aafs


# Local variables:
# mode: shell-script
# sh-basic-offset: 8
# tab-width: 8
# End:
# vi: set sw=8 ts=8
