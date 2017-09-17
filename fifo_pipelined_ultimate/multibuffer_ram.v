//`default_nettype none

// Byte addressable read
module multi_buffer_ram #(
	parameter DATA_WIDTH = 128,
	parameter DATA_OUT_WIDTH = 64,
	parameter ADDR_WIDTH = 10,
	parameter BUFF_NUM = 4
) (
	input clk,
	input rst,
	input write_en,
	input[(ADDR_WIDTH-1)+$clog2(BUFF_NUM):0] write_addr,
	input[DATA_WIDTH-1:0] data_in,
	input read_en,
	input[(ADDR_WIDTH+$clog2(DATA_WIDTH/8)-1)+$clog2(BUFF_NUM):0] read_addr,
	output[DATA_OUT_WIDTH-1:0] q
	);

genvar i;

// Renaming (unpacking)
wire[$clog2(BUFF_NUM)-1:0] write_buffer_idx, read_buffer_idx;
wire[ADDR_WIDTH-1:0] write_buffer_addr, read_buffer_addr;
wire[$clog2(DATA_WIDTH/8)-1:0] byte_offset;
assign {write_buffer_idx, write_buffer_addr} = write_addr;
assign {read_buffer_idx, read_buffer_addr, byte_offset} = read_addr;

// Separating
wire even_odd_bit;
reg[$clog2(BUFF_NUM)-1:0] read_even_buffer_idx, read_odd_buffer_idx;
reg[ADDR_WIDTH-2:0] read_even_buffer_addr, read_odd_buffer_addr;

assign even_odd_bit = read_buffer_addr[0];
always@ (*) begin
	if (!even_odd_bit) begin
		{read_even_buffer_idx, read_even_buffer_addr} = {read_buffer_idx, read_buffer_addr[ADDR_WIDTH-1:1]};
	end
	else begin
		{read_even_buffer_idx, read_even_buffer_addr} = {read_buffer_idx, read_buffer_addr[ADDR_WIDTH-1:1]} + 1'd1;
	end
	read_odd_buffer_addr = read_buffer_addr[ADDR_WIDTH-1:1];
	read_odd_buffer_idx = read_buffer_idx;
end

// Add pipeline between RAM and MUX
wire[DATA_WIDTH-1:0] even_buffer_q[0:BUFF_NUM-1], odd_buffer_q[0:BUFF_NUM-1];
reg[DATA_OUT_WIDTH-1:0] buffer_q_pipelined[0:BUFF_NUM];

// Output
wire[$clog2(BUFF_NUM)-1:0] q_even_buffer_idx, q_odd_buffer_idx;
wire[$clog2(DATA_WIDTH/8)-1:0] q_byte_offset;
wire q_even_odd_bit;

pipeline_helper #(
	.PIPELINE_LEVEL(1),
	.SIGNAL_WIDTH(
		$clog2(BUFF_NUM)    // q_odd_buffer_idx
		+ $clog2(BUFF_NUM)  // q_even_buffer_idx
		+ 1                 // Even/Odd bit
	)
) pipeline_u0 (
	clk,
	{read_odd_buffer_idx, read_even_buffer_idx, even_odd_bit},
	{q_odd_buffer_idx, q_even_buffer_idx, q_even_odd_bit}
	);

pipeline_helper #(
	.PIPELINE_LEVEL(2),
	.SIGNAL_WIDTH(
		$clog2(DATA_WIDTH/8) // q_byte_offset
	)
) pipeline_u1 (
	clk,
	{byte_offset},
	{q_byte_offset}
	);

reg[DATA_WIDTH-1:0] lower_buffer_q, upper_buffer_q;
always@ (posedge clk) begin
	if (q_even_odd_bit == 1'b0) begin
		lower_buffer_q <= even_buffer_q[q_even_buffer_idx];
		upper_buffer_q <= odd_buffer_q[q_odd_buffer_idx];
	end
	else begin
		lower_buffer_q <= odd_buffer_q[q_odd_buffer_idx];
		upper_buffer_q <= even_buffer_q[q_even_buffer_idx];
	end
end

// Set output to the right offset of data
wire[DATA_OUT_WIDTH-1:0] q_sellector[0:(DATA_WIDTH/8)-1];
generate
	for (i = 0; i < DATA_WIDTH/8; i = i + 1) begin : multi_buff_byte_offset
		if (i + DATA_OUT_WIDTH/8 <= DATA_WIDTH/8) begin
			assign q_sellector[i] = lower_buffer_q[(i*8)+DATA_OUT_WIDTH-1:i*8];
		end
		else begin
			assign q_sellector[i] = {upper_buffer_q[(DATA_OUT_WIDTH-1)-(DATA_WIDTH-(i*8)):0], lower_buffer_q[DATA_WIDTH-1:i*8]};
		end
	end
endgenerate
assign q = q_sellector[q_byte_offset];

// Enable signals
wire write_buffer_enable[0:BUFF_NUM-1];
wire read_even_buffer_enable[0:BUFF_NUM-1], read_odd_buffer_enable[0:BUFF_NUM-1];
generate
	for (i = 0; i < BUFF_NUM; i = i + 1) begin : multi_buff_enable
		assign write_buffer_enable[i] = (write_buffer_idx == i);
		assign read_even_buffer_enable[i] = (read_even_buffer_idx == i);
		assign read_odd_buffer_enable[i] = (read_odd_buffer_idx == i);
	end
endgenerate

// Multi-buffer
generate
	for (i = 0; i < BUFF_NUM; i = i + 1) begin : multi_buff
		ram_block #(
			.ADDR_WIDTH(ADDR_WIDTH - 1),
			.DATA_WIDTH(DATA_WIDTH)
		) q_mem_block_even (
			clk,
			write_en & write_buffer_enable[i] & ~write_buffer_addr[0],
			write_buffer_addr[ADDR_WIDTH-1:1],
			data_in,
			read_en & read_even_buffer_enable[i],
			read_even_buffer_addr,
			even_buffer_q[i]
			);
		ram_block #(
			.ADDR_WIDTH(ADDR_WIDTH - 1),
			.DATA_WIDTH(DATA_WIDTH)
		) q_mem_block_odd (
			clk,
			write_en & write_buffer_enable[i] & write_buffer_addr[0],
			write_buffer_addr[ADDR_WIDTH-1:1],
			data_in,
			read_en & read_odd_buffer_enable[i],
			read_odd_buffer_addr,
			odd_buffer_q[i]
			);
	end
endgenerate

endmodule
