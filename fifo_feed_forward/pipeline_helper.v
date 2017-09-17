`default_nettype none

module pipeline_helper #(
	parameter PIPELINE_LEVEL = 2,
	parameter SIGNAL_WIDTH = 1
) (
	input clk,
	input[SIGNAL_WIDTH-1:0] p_signals_in,
	output[SIGNAL_WIDTH-1:0] p_signals_out
	);

genvar i;

reg[SIGNAL_WIDTH-1:0] p_signals[0:PIPELINE_LEVEL-1];
always @(posedge clk) begin
	p_signals[0] <= p_signals_in;
end
assign p_signals_out = p_signals[PIPELINE_LEVEL-1];

// Pipeline the control signal to the output
generate
	for (i = 1; i < PIPELINE_LEVEL; i = i + 1) begin : pipeline_signals
		always @(posedge clk) begin
			p_signals[i] <= p_signals[i - 1];
		end
	end
endgenerate

endmodule
