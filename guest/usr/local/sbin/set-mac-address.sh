#!/bin/bash

set -e

export LANG=C

MAC=$(hostname|sed -e 's/.*-//')

# if ifconfig $1 hw ether $MAC; then exit 0; else exit 1; fi
