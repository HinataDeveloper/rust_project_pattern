#!/usr/bin/env zsh

clear
zsh ./ncopy6.zsh run
git status
git add --all
git commit -m $1
git push origin
printf " Commit was down successfully ...\n\n"