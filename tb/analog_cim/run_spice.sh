#!/bin/bash
ngspice -b smoke_test.spice < /dev/null > smoke_test.out 2>&1
cat smoke_test.out
