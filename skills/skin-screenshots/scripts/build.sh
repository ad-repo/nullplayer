#!/bin/bash
# Compiles winhelper (window enumeration + real CGEvent clicks). Idempotent.
set -e
cd "$(dirname "$0")"
if [ ! -x winhelper ] || [ winhelper.swift -nt winhelper ]; then
  swiftc -O -o winhelper winhelper.swift
  echo "built winhelper"
else
  echo "winhelper up to date"
fi
