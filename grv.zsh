#!/bin/env zsh

{ rustc -Vv && echo "" && cargo -Vv; } | sed 's/^/\/\/ /' > rust_version.txt
