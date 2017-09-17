//`default_nettype none

module multibuffer_queue #(
	parameter Q_DATA_WIDTH = 128,
	parameter M_BUFF_NUM = 4,
	parameter M_BUFF_ADDR_WIDTH = 10,
	parameter DATA_OUT_WIDTH = 64
) (
	input clk,
	input rst,
	// Write control
	input write_en,
	input[Q_DATA_WIDTH-1 : 0] data_in,
	output waitrequest, // Cannot accept input data when high
	// Read control
	input read_en,
	output reg[DATA_OUT_WIDTH-1 : 0] data_out,
	output data_valid, // Output data is valid for read when high
	// Output control
	output reg full,  // QUEUE is full when high
	output reg empty, // Queue is empty when high
	// Advanced input control
	output reg almost_full // One block away before it's full
	);

localparam BUFF_ADDR_MSB = (M_BUFF_ADDR_WIDTH - 1) + $clog2(M_BUFF_NUM);
localparam SUB_BUFF_WIDTH = $clog2(Q_DATA_WIDTH/DATA_OUT_WIDTH);
genvar i;

reg[BUFF_ADDR_MSB:0] write_addr;
reg[BUFF_ADDR_MSB:0] read_addr;
reg[SUB_BUFF_WIDTH-1:0] sub_buffer_addr;

// These two are used to remember the counter value in IDLE state so that we can recover the value from it.
reg[SUB_BUFF_WIDTH-1:0] sub_buffer_addr_idle;

// Renaming the buffer index and buffer address (unpacking)
wire[$clog2(M_BUFF_NUM)-1:0] write_buffer_idx, read_buffer_idx;
wire[M_BUFF_ADDR_WIDTH-1:0] write_buffer_addr, read_buffer_addr;
assign {write_buffer_idx, write_buffer_addr} = write_addr;
assign {read_buffer_idx, read_buffer_addr} = read_addr;

wire waitrequest_w, waitrequest_r;
wire p_waitrequest_r; // The waitrequest_r after pipeline. Same timing as output signals.

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

wire[SUB_BUFF_WIDTH-1:0] p_sub_buffer_addr;
wire valid_addr_flag;
always @(posedge clk, posedge rst) begin
	if(rst) begin
		{read_addr, sub_buffer_addr} <= 'd0;
	end
	else begin
		if (read_en && !waitrequest_r) begin
			{read_addr, sub_buffer_addr} <=
				{read_addr, sub_buffer_addr} + 1'd1;
		end
	end
end
assign valid_addr_flag = (read_en && !waitrequest_r);

// Higher truncated bit not only help speed as well as the frequency of full being high
localparam TRUNCATE_BIT = 4;
always @(posedge clk) begin
	full <= (write_addr[BUFF_ADDR_MSB:TRUNCATE_BIT] + 1'd1 == read_addr[BUFF_ADDR_MSB:TRUNCATE_BIT]);
	empty <= p_waitrequest_r;
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
assign waitrequest_w = full; // Wait condition for internal use
assign waitrequest_r = (write_addr == read_addr); // Wait condition for internal use


// Connect to the MultiBuffer RAM
wire[Q_DATA_WIDTH-1:0] buffer_q_o;
reg[Q_DATA_WIDTH-1:0] buffer_q;
wire[DATA_OUT_WIDTH-1:0] packet_data_wire[0:2**SUB_BUFF_WIDTH];
generate
	for (i = 0; i < 2**SUB_BUFF_WIDTH; i = i + 1) begin : pack_data
		assign packet_data_wire[i] = buffer_q[((i+1)*DATA_OUT_WIDTH)-1:i*DATA_OUT_WIDTH];
	end
endgenerate

// Unpack data to output
always@ (posedge clk) begin
	buffer_q <= buffer_q_o;
	data_out <= packet_data_wire[p_sub_buffer_addr];
end

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
	buffer_q_o
	);

pipeline_helper #(
	.PIPELINE_LEVEL(3),
	.SIGNAL_WIDTH(
		+ SUB_BUFF_WIDTH    // p_sub_buffer_addr
		+ 1                 // p_waitrequest_r
	)
) pipeline_u0 (
	clk,
	{sub_buffer_addr, waitrequest_r},
	{p_sub_buffer_addr, p_waitrequest_r}
	);

pipeline_helper #(
	.PIPELINE_LEVEL(4),
	.SIGNAL_WIDTH(
		+ 1 // data_valid
	)
) pipeline_u1 (
	clk,
	{valid_addr_flag},
	{data_valid}
	);

endmodule

