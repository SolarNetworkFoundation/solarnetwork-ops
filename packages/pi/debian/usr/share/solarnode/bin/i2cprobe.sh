#!/bin/sh
modprobe ${MODALIAS} || modprobe "of:N${OF_NAME}T<NULL>C${OF_COMPATIBLE_0}"

