#!/usr/bin/env bash
iverilog -o sim/tb_MMU.vvp sim/*.v rtl/*.v
vvp sim/tb_MMU.vvp
