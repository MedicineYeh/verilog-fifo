# Verilog FIFO
This is an open source FIFO implementation for connecting with PCIe device.
This was designed to hook the interface of [RIFFA](https://github.com/KastnerRG/riffa)
which is a nice open source framework as a startting point for writting your own PCIe acceleration functions on FPGA card.

## Design Principle
In order to provide a queue with large on-chip memory, we implemented this under a concept called logic RAM.
The design uses multiple small RAMs to assemble a large RAM, so that it does not cause a bottleneck on clock timing.

The FIFO was designed with a fixed 128-bit input and variable width output.
There are four different implementations which should be enough for different usages.

## fifo_basic
This is the basic one-clock cycle design with no pipeline.

## fifo_feed_forward
This is the simple feed-forward pipelined version of FIFO.
In this module, read_en is used as data control.
The data would be read out as many as the number of cycles when read_en was high.
In practice, this version is the fatest version since all the data are pipelined to the output and do not feed back to the input.

It's highly recommanded to use this module if your module is aware of the number of cycles (3-cycle) in the pipeline.
One can even use this module to control the frequency of output data, i.e. 1-data/2-cycle, by keeping the read_en high and low for 2 cycles.

## fifo_pipelined
This is a complete and full-function FIFO implementation with pipeline.
In this module, read_en is used as a output control.
If the reader cannot take any data at any cycle, it can simplily set read_en to low.
However, there is a drawback of cold boot after read_en is set to high.

## fifo_pipelined_ultimate
All of the above implementations accept 8/16/32/64/128 output data width.
However, sometimes, the user defined data packets might be 72-bit, which would waste the rest 56-bit under the restriction of 128-bit alignment.
To solve this problem, this module further implements a byte-addressable (read-only) RAM.
This provides any size of data packets output as long as the size is aligned to 8-bit (1-byte).


# License
MIT License
