`default_nettype none

module ram_block #(
	parameter ADDR_WIDTH = 10,
	parameter DATA_WIDTH = 128
) (
	input clk,
	input write_en,
	input [ADDR_WIDTH-1:0] write_addr,
	input [DATA_WIDTH-1:0] data_in,
	input read_en,
	input [ADDR_WIDTH-1:0] read_addr,
	output reg [DATA_WIDTH-1:0] q
	);

reg[DATA_WIDTH-1:0] ram_data[0:2**ADDR_WIDTH-1];


always@(posedge clk) begin
	if (write_en) begin
		ram_data[write_addr] <= data_in;
	end
	if (read_en) begin
		q <= ram_data[read_addr];
	end
end
endmodule
