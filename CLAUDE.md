# iigs simulation

## Project Description

This project contains and unfinished iigs simulation written in verilog. There is a vsim directory with a Makefile that allows the simulation to run in a window. It produces debug output on the stdout including instruction dumps from the CPU.

## Layout and Running the simulation

The simulator must be started from the vsim directory as the working directory, because of relative file paths. In the top level are some md files that help describe the architecture. These are distilled from the source documentation in the doc folder. Also there are sample emulators written in c inside the software_emulators folder.
