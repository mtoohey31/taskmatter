#!/bin/sh

if [ ! -d "completions" ]; then
  mkdir completions
fi

register-python-argcomplete --shell bash taskmatter > completions/taskmatter-completion.bash
cp completions/taskmatter-completion.bash completions/_taskmatter
register-python-argcomplete --shell tcsh taskmatter > completions/taskmatter-complete.tcsh
register-python-argcomplete --shell fish taskmatter > completions/taskmatter.fish
