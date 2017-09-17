//`default_nettype none

module multibuffer_queue #(
	parameter Q_DATA_WIDTH = 128,
	parameter M_BUFF_NUM = 4,
	parameter M_BUFF_ADDR_WIDTH = 10,
	parameter DATA_OUT_WIDTH = 42
) (
	input clk,
	input rst,
	// Write control
	input write_en,
	input[Q_DATA_WIDTH-1 : 0] data_in,
	output waitrequest, // Cannot accept input data when high
	// Read control
	input read_en,
	output[DATA_OUT_WIDTH-1 : 0] data_out,
	output reg data_valid, // Output data is valid for read when high
	// Output control
	output full,  // QUEUE is full when high
	output empty, // Queue is empty when high
	// Advanced input control
	output reg almost_full // One block away before it's full
	);

localparam BUFF_ADDR_MSB = (M_BUFF_ADDR_WIDTH - 1) + $clog2(M_BUFF_NUM);
genvar i;

reg[BUFF_ADDR_MSB:0] write_addr;
reg[BUFF_ADDR_MSB:0] read_addr;
reg[0:0] sub_buffer_addr, p_sub_buffer_addr;

// Renaming the buffer index and buffer address (unpacking)
wire[$clog2(M_BUFF_NUM)-1:0] write_buffer_idx, read_buffer_idx;
wire[M_BUFF_ADDR_WIDTH-1:0] write_buffer_addr, read_buffer_addr;
assign {write_buffer_idx, write_buffer_addr} = write_addr;
assign {read_buffer_idx, read_buffer_addr} = read_addr;

wire waitrequest_w, waitrequest_r;

always @(posedge clk, posedge rst) begin
	if (rst) begin
		write_addr <= 'd0;
	end
	else begin
		if (write_en && !waitrequest_w) begin
			write_addr <= write_addr + 1'd1;
		end
	end
end

always @(posedge clk, posedge rst) begin
	if(rst) begin
		{read_addr, sub_buffer_addr} <= 'd0;
		data_valid <= 1'b0;
	end
	else begin
		if (read_en && !waitrequest_r) begin
			{read_addr, sub_buffer_addr} <=
				{read_addr, sub_buffer_addr} + 1'd1;
			data_valid <= 1'b1;
		end
		else begin
			data_valid <= 1'b0;
		end
	end
end

// Critical Path
// Higher truncated bit not only help speed as well as the frequency of full being high
localparam TRUNCATE_BIT = 4;
assign full = (write_addr[BUFF_ADDR_MSB:TRUNCATE_BIT] + 1'd1 == read_addr[BUFF_ADDR_MSB:TRUNCATE_BIT]);
assign empty = (write_addr == read_addr);
// Set pipelined_full as wire and assign it to full if you don't need pipelined output
reg pipelined_full;
always @(posedge clk) begin
	pipelined_full <= full;
    p_sub_buffer_addr <= sub_buffer_addr;
end

// Begin of almost_full
always @(posedge clk) begin
	if (write_buffer_idx + 1'd1 == read_buffer_idx)
		almost_full <= 1'b1;
	else if (write_buffer_idx == read_buffer_idx)
		almost_full <= write_buffer_addr < read_buffer_addr;
end
// End of almost_full

// Set up the signals of waitrequests
assign waitrequest = full; // Wait condition for interface
assign waitrequest_w = pipelined_full; // Wait condition for internal use
assign waitrequest_r = empty; // Wait condition for internal use


// Connect to the MultiBuffer RAM
wire[Q_DATA_WIDTH-1:0] buffer_q;
wire[41:0] packet_data_wire[0:1];
assign packet_data_wire[1] = buffer_q[105:64];
// [63:41] is unused write_addr[11:10]
assign packet_data_wire[0] = buffer_q[41:0];
// Unpack data to output
assign data_out = packet_data_wire[p_sub_buffer_addr][41:0];

multi_buffer_ram #(
	.DATA_WIDTH(Q_DATA_WIDTH),
	.ADDR_WIDTH(M_BUFF_ADDR_WIDTH),
	.BUFF_NUM(M_BUFF_NUM)
) ram_u0 (
	clk,
	rst,
	(write_en & ~waitrequest_w),
	write_addr,
	data_in,
	(read_en & ~waitrequest_r),
	read_addr,
	buffer_q
	);

endmodule

