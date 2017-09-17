//`default_nettype none

module multibuffer_queue #(
	parameter Q_DATA_WIDTH = 128,
	parameter M_BUFF_NUM = 4,
	parameter M_BUFF_ADDR_WIDTH = 10,
	parameter DATA_OUT_WIDTH = 48
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
	output reg data_valid, // Output data is valid for read when high
	// Output control
	output reg full,  // QUEUE is full when high
	output reg empty, // Queue is empty when high
	// Advanced input control
	output reg almost_full // One block away before it's full
	);

localparam DATA_OUT_SIZE = DATA_OUT_WIDTH / 8;

localparam BUFF_ADDR_MSB = (M_BUFF_ADDR_WIDTH - 1) + $clog2(M_BUFF_NUM);
localparam SUB_BUFF_WIDTH = 4; // For counting 16 bytes offset.
genvar i;

reg[BUFF_ADDR_MSB:0] write_addr;
reg[BUFF_ADDR_MSB:0] read_addr;
reg[SUB_BUFF_WIDTH-1:0] sub_buffer_addr;

// These two are used to remember the counter value in IDLE state so that we can recover the value from it.
reg[BUFF_ADDR_MSB:0] read_addr_idle;
reg[SUB_BUFF_WIDTH-1:0] sub_buffer_addr_idle;

// Renaming the buffer index and buffer address (unpacking)
wire[$clog2(M_BUFF_NUM)-1:0] write_buffer_idx, read_buffer_idx;
wire[M_BUFF_ADDR_WIDTH-1:0] write_buffer_addr, read_buffer_addr;
assign {write_buffer_idx, write_buffer_addr} = write_addr;
assign {read_buffer_idx, read_buffer_addr} = read_addr;

wire waitrequest_w, waitrequest_r;
wire p_waitrequest_r; // The waitrequest_r after pipeline. Same timing as output signals.

reg[1:0] state;
localparam IDLE = 2'd0, ISSUE_READ = 2'd1, READ = 2'd3, BURST_READ = 2'd2;
always @(posedge clk) begin
	if (rst) begin
		state <= IDLE;
		data_valid <= 1'b0;
		empty <= 1'b1;
	end
	else begin
		case (state)
			IDLE: begin
				if (read_en && !waitrequest_r) state <= ISSUE_READ;
				empty <= waitrequest_r;
				read_addr_idle <= read_addr;
				sub_buffer_addr_idle <= sub_buffer_addr;
			end
			ISSUE_READ: begin
				state <= (read_en) ? READ : IDLE;
			end
			READ: begin
				state <= (read_en) ? BURST_READ : IDLE;
				data_valid <= 1'b1;
				empty <= p_waitrequest_r;
			end
			BURST_READ: begin
				if (!read_en || p_waitrequest_r) begin
					state <= IDLE;
					data_valid <= 1'b0;
				end
				if (p_waitrequest_r) empty <= 1'b1;
			end
		endcase
	end
end

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

wire[BUFF_ADDR_MSB:0] read_addr_recover;
wire[SUB_BUFF_WIDTH-1:0] p_sub_buffer_addr;
always @(posedge clk, posedge rst) begin
	if(rst) begin
		{read_addr, sub_buffer_addr} <= 'd0;
	end
	else begin
		if (read_en && !waitrequest_r) begin
			{read_addr, sub_buffer_addr} <=
				{read_addr, sub_buffer_addr} + DATA_OUT_SIZE;
		end
		else if (!read_en && !p_waitrequest_r) begin
			if (data_valid) // Stable abort. Reset the counter to the pipelined value.
				{read_addr, sub_buffer_addr} <= {read_addr_recover, p_sub_buffer_addr};
			else // Unstable abort. Reset the counter to its IDLE state
				{read_addr, sub_buffer_addr} <= {read_addr_idle, sub_buffer_addr_idle};
		end
	end
end

// Higher truncated bit not only help speed as well as the frequency of full being high
localparam TRUNCATE_BIT = 4;
always @(posedge clk) begin
	full <= (write_addr[BUFF_ADDR_MSB:TRUNCATE_BIT] + 1'd1 == read_addr[BUFF_ADDR_MSB:TRUNCATE_BIT]);
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
wire[DATA_OUT_WIDTH-1:0] buffer_q;
// Unpack data to output
always@ (posedge clk) begin
	data_out <= buffer_q;
end

multi_buffer_ram #(
	.DATA_WIDTH(Q_DATA_WIDTH),
	.DATA_OUT_WIDTH(DATA_OUT_WIDTH),
	.ADDR_WIDTH(M_BUFF_ADDR_WIDTH),
	.BUFF_NUM(M_BUFF_NUM)
) ram_u0 (
	clk,
	rst,
	(write_en & ~waitrequest_w),
	write_addr,
	data_in,
	(read_en & ~waitrequest_r),
	{read_addr, sub_buffer_addr},
	buffer_q
	);

pipeline_helper #(
	.PIPELINE_LEVEL(2),
	.SIGNAL_WIDTH(
		(BUFF_ADDR_MSB + 1) // read_addr_out
		+ SUB_BUFF_WIDTH    // p_sub_buffer_addr
		+ 1                 // p_waitrequest_r
	)
) pipeline_u0 (
	clk,
	{read_addr, sub_buffer_addr, waitrequest_r},
	{read_addr_recover, p_sub_buffer_addr, p_waitrequest_r}
	);

endmodule

