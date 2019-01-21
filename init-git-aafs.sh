#!/bin/sh
#
# $ init-git-aafs.sh $
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#       Copyright (c) 2019 Tomi Ollila
#           All rights reserved
#
# Created: Mon 21 Jan 2019 20:12:43 EET too
# Last modified: Mon 21 Jan 2019 23:00:12 +0200 too

# SPDX-License-Identifier: BSD-2-Clause

case ~ in '~') echo "'~' does not expand. old /bin/sh?" >&2; exit 1; esac

case ${BASH_VERSION-} in *.*) set -o posix; shopt -s xpg_echo; esac
case ${ZSH_VERSION-} in *.*) emulate ksh; esac

set -euf

saved_IFS=$IFS; readonly saved_IFS

warn () { printf '%s\n' "$*"; } >&2
die () { printf '%s\n' "$@"; exit 1; } >&2

x () { printf '+ %s\n' "$*" >&2; "$@"; }
x_env () { printf '+ %s\n' "$*" >&2; env "$@"; }
x_eval () { printf '+ %s\n' "$*" >&2; eval "$*"; }
x_exec () { printf '+ %s\n' "$*" >&2; exec "$@"; die "exec '$*' failed"; }

case ${1-} in --debug) dbgopt=--debug; shift ;; *) dbgopt= ;; esac

test $# = 3 || die '' \
	"Usage: $0 [--debug] gitdir repourl encryption-type" '' \
	"example: $0 . $USER@localhost:aafs none" '' \
        'note: will execute  git config remote.origin.annex-ignore true' ''

command -v git-annex-remote-git-aafs >/dev/null || die '' \
	"'git-annex-remote-git-aafs' not in \$PATH" ''

x cd "$1"

test -d .git || die "'$1/.git' is nonexistent or not directory..."

for c in user.name user.email
do
	git config $c >/dev/null || die '' \
		"'$c' not defined. Use git-config $c ... to configure" ''
done

if test -e .git/annex
then die '' "'$1/.git/annex' exists... you can perhaps remove it and retry" ''
fi

xh=false
for h in pre-commit post-receive
do
	if test -e .git/hooks/$h
	then
		warn "'$1/.git/hooks/$h' exists"
		xh=true
	fi
done

if $xh
then
	die  '' "git-annex does not overwrite git hooks (so we stop)..." \
		"hint: mv(1) above hook(s) away, try again and then merge" ''
fi

x pwd
x git-annex $dbgopt init
echo :
x git config remote.origin.annex-ignore true
echo :
x git-annex $dbgopt initremote git-aafs type=external externaltype=git-aafs \
        encryption="$3" repo="$2"


# Local variables:
# mode: shell-script
# sh-basic-offset: 8
# tab-width: 8
# End:
# vi: set sw=8 ts=8
