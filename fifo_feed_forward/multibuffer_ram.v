//`default_nettype none

module multi_buffer_ram #(
	parameter DATA_WIDTH = 128,
	parameter ADDR_WIDTH = 10,
	parameter BUFF_NUM = 4
) (
	input clk,
	input rst,
	input write_en,
	input [(ADDR_WIDTH-1)+$clog2(BUFF_NUM):0] write_addr,
	input [DATA_WIDTH-1:0] data_in,
	input read_en,
	input [(ADDR_WIDTH-1)+$clog2(BUFF_NUM):0] read_addr,
	output [DATA_WIDTH-1:0] q
	);

genvar i;

// Renaming (unpacking)
wire[$clog2(BUFF_NUM)-1:0] write_buffer_idx, read_buffer_idx;
wire[ADDR_WIDTH-1:0] write_buffer_addr, read_buffer_addr;
assign {write_buffer_idx, write_buffer_addr} = write_addr;
assign {read_buffer_idx, read_buffer_addr} = read_addr;

// Add pipeline between RAM and MUX
wire[DATA_WIDTH-1:0] buffer_q[0:BUFF_NUM-1];
reg[DATA_WIDTH-1:0] buffer_q_pipelined[0:BUFF_NUM];

// Output
reg[$clog2(BUFF_NUM)-1:0] q_buffer_idx;
reg[$clog2(BUFF_NUM)-1:0] q_buffer_idx_pipelined; // Pipeline output control signal
always @(posedge clk) begin
	q_buffer_idx <= read_buffer_idx;
	q_buffer_idx_pipelined <= q_buffer_idx;
end
assign q = buffer_q_pipelined[q_buffer_idx_pipelined];

// Enable signals
wire write_buffer_enable[0:BUFF_NUM-1];
wire read_buffer_enable[0:BUFF_NUM-1];
generate
	for (i = 0; i < BUFF_NUM; i = i + 1) begin : multi_buff_enable
		assign write_buffer_enable[i] = (write_buffer_idx == i);
		assign read_buffer_enable[i] = (read_buffer_idx == i);
		always @(posedge clk) begin
			buffer_q_pipelined[i] <= buffer_q[i];
		end
	end
endgenerate

// Multi-buffer
generate
	for (i = 0; i < BUFF_NUM; i = i + 1) begin : multi_buff
		ram_block #(
			.ADDR_WIDTH(ADDR_WIDTH),
			.DATA_WIDTH(DATA_WIDTH)
		) q_mem_block (
			clk,
			write_en & write_buffer_enable[i],
			write_buffer_addr,
			data_in,
			read_en & read_buffer_enable[i],
			read_buffer_addr,
			buffer_q[i]
			);
	end
endgenerate

endmodule
