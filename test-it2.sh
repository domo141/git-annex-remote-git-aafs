#!/bin/sh
#
# Created: Fri 28 Dec 2018 20:45:48 +0200 too
# Last modified: Mon 31 Dec 2018 16:35:10 +0200 too

# SPDX-License-Identifier: BSD-2-Clause

case ${BASH_VERSION-} in *.*) set -o posix; shopt -s xpg_echo; esac
case ${ZSH_VERSION-} in *.*) emulate ksh; esac

set -euf

LANG=C.UTF-8 LC_ALL=C.UTF-8; export LANG LC_ALL; unset LANGUAGE

die () { printf '%s\n' "$*"; exit 1; } >&2

test -d tdir && rm -f tdir/latest || mkdir tdir
td=`exec mktemp -d tdir/kXXXXX.git`
ln -sf ${td#*/} tdir/latest

perl -pe 's/(?=git ls-remote)/true /' \
	git-annex-remote-git-aafs.pl > $td/test-initremote-repos.pl

set -x
:
diff -U1 git-annex-remote-git-aafs.pl $td/test-initremote-repos.pl || :

PATH=$PWD/tdir:$PATH; export PATH
cd $td
:
git init --template=/dev/null
:
git config user.email "aafs@example.org"
git config user.name "git annex addressable file storage test"
:
set +x

test -p co.fifo || mkfifo co.fifo

c=0
vread () {
	read cmd arg rest
	echo $c: read: $cmd : $arg : $rest : >&2
	if test $# -ge 1
	then test "$1" = "$cmd" || die "cmd: '$cmd' != '$1'"
	fi
	if test $# -ge 2
	then test "$2" = "$arg" || die "arg: '$arg' != '$2'"
	fi
	if test $# -ge 3
	then test "$3" = "$rest" || die "rest: '$rest' != '$3'"
	fi
}

vecho () {
	echo $c: send: "$@" >&2
	echo "$@"
}

ru=
test_it ()
{
	c=$((c + 1)); echo test_it $c: "$1 $2 -- $ru"
{
	trap "kill -USR1 $$" 0
	vread VERSION 1
	vecho INITREMOTE
	vread GETCONFIG repo
	vecho VALUE "$1"
	test "$2" = - ||
	vread SETCONFIG repo "$2"
	vread INITREMOTE-SUCCESS
	trap - 0
} < co.fifo | perl ./test-initremote-repos.pl > co.fifo
}

test_it2 () {
	test_it "$1"  "$2"
	test_it "$1"/ "$2"
}

trap 'exit 1' USR1

git () {
	test "$1" = config && test "$2" = remote.origin.url && ru=$3 || :
	command git "$@"
}

git config remote.origin.url git://a.b@c.de/repo/

test_it -aafs      git://a.b@c.de/repo-aafs/
test_it -aafs.git  git://a.b@c.de/repo-aafs.git/

git config remote.origin.url git://a.b@c.de/repo.git

test_it -aafs      git://a.b@c.de/repo-aafs.git/
test_it -aafs.git  git://a.b@c.de/repo-aafs.git/

test_it2 .          git://a.b@c.de/repo.git/
test_it2 ..         git://a.b@c.de/
test_it2 ../..      git://a.b@c.de/
test_it2 /f         git://a.b@c.de/f/
test_it2 /          git://a.b@c.de/
test_it2 /..        git://a.b@c.de/

git config remote.origin.url a.b@c.de:/path/to/repo.git

test_it -aafs      a.b@c.de:/path/to/repo-aafs.git/
test_it -aafs.git  a.b@c.de:/path/to/repo-aafs.git/

test_it2 .             a.b@c.de:/path/to/repo.git/
test_it2 ..            a.b@c.de:/path/to/
test_it2 ../..         a.b@c.de:/path/
test_it2 ../../repo    a.b@c.de:/path/repo/
test_it2 ../../..      a.b@c.de:/
test_it2 ../../../..   a.b@c.de:/

git config remote.origin.url a.b@c.de:path/to/repo/

test_it2 .             a.b@c.de:path/to/repo/
test_it2 ../../../..   a.b@c.de:../

ru=local

test_it2 :.         ./
test_it2 :..        ../
test_it2 :/         /
test_it2 :/..       /
test_it2 :aafs      aafs/
test_it2 :aafs/.    aafs/
test_it2 :/aafs/..  /
test_it2 :aafs/..   ./

test_it2 https://aafs.example.org/too.git  https://aafs.example.org/too.git/
test_it2 https://aafs.example.org/..       https://aafs.example.org/
test_it2 https://aafs.example.org/../..    https://aafs.example.org/

test_it2 aafs.example.org:too.git  aafs.example.org:too.git/
test_it2 aafs.example.org:..       aafs.example.org:../
test_it2 aafs.example.org:../..    aafs.example.org:../../

test_it2 aafs.example.org:/too.git  aafs.example.org:/too.git/
test_it2 aafs.example.org:/..       aafs.example.org:/
test_it2 aafs.example.org:/../..    aafs.example.org:/


echo
echo kaikki meni
echo

# Local variables:
# mode: shell-script
# sh-basic-offset: 8
# tab-width: 8
# End:
# vi: set sw=8 ts=8
