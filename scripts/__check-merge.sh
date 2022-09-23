#!/bin/bash
currentBranch=$(git branch --show-current)

git checkout main
git merge --no-commit --no-ff $currentBranch 
echo $? 
git merge --abort
git checkout $currentBranch
