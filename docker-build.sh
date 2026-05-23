#!/usr/bin/env bash
docker build --no-cache --progress plain "$@" --tag=jammsen/palworld-dedicated-server:latest .