//`default_nettype none

module p_multibuffer_queue #(
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
	output reg waitrequest, // Cannot accept input data when high
	// Read control
	input read_en,
	output reg[DATA_OUT_WIDTH-1 : 0] data_out,
	output reg data_valid, // Output data is valid for read when high
	// Output control
	output reg full,  // QUEUE is full when high
	output reg empty, // Queue is empty when high
	// Advanced input control
	output almost_full // One block away before it's full
	);

wire waitrequest_o;
wire full_o;
wire empty_o;
wire data_valid_o;
wire[DATA_OUT_WIDTH-1 : 0] data_out_o;

always @(posedge clk) begin
	waitrequest <= waitrequest_o;
	data_valid <= data_valid_o;
	full <= full_o;
	empty <= empty_o;
	data_out <= data_out_o;
	// Use the following code if you want to mask out the data when invalid
	// access_info <= (data_valid_o) ? access_info_o : 'd0;
	// memory_access <= (data_valid_o) ? memory_access_o : 'd0;
end

multibuffer_queue #(
	.Q_DATA_WIDTH(Q_DATA_WIDTH),
	.M_BUFF_NUM(M_BUFF_NUM),
	.M_BUFF_ADDR_WIDTH(M_BUFF_ADDR_WIDTH),
	.DATA_OUT_WIDTH(DATA_OUT_WIDTH)
) mutiple_buffer (
	.clk(clk),
	.rst(rst),
	.write_en(write_en),
	.data_in(data_in),
	.waitrequest(waitrequest_o),
	.read_en(read_en),
	.data_out(data_out_o),
	.data_valid(data_valid_o),
	.full(full_o),
	.empty(empty_o),
	.almost_full(almost_full)
	);

endmodule
