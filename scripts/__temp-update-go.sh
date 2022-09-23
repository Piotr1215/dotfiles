#!/usr/bin/env bash

export GOROOT="$(go1.18rc1 env GOROOT)"
export PATH="$(go1.18rc1 env GOROOT)/bin":$PATH
