#!/bin/env bash

rm -rf src/.main.rs.bak*
git add --all
git commit -m 'New Rust sample code for review'
git status
