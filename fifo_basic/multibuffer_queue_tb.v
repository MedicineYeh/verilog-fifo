//`default_nettype none
`timescale 1ns/10ps
`define CYCLE 20

module multibuffer_queue_tb;

parameter Q_DATA_WIDTH = 128;
parameter INFO_WIDTH = 10;
parameter ADDR_WIDTH = 32;
parameter M_BUFF_ADDR_WIDTH = 10;

reg clk;
reg rst;
reg write_en;
reg [Q_DATA_WIDTH-1:0] data_in;
wire waitrequest;
reg read_en;
wire [INFO_WIDTH-1:0] access_info;
wire [ADDR_WIDTH-1:0] memory_access;
wire data_valid;
wire full;
wire empty;
wire almost_full;

initial begin
	clk = 0;
	#5; // Shift clock just a bit
	forever #10 clk = ~clk;
end

integer error = 0;
integer i = 0;
integer parallel_read_finish = 0;
integer do_parallel_test = 0;

task reset;
	begin
		write_en = 1'b0;
		data_in = 128'b0;
		read_en = 1'b0;
	end
endtask

task write_data;
	input not_first_time_access;
	input [3:0]core_id;
	input [2:0]read_write;
	input [1:0]stop;
	input [31:0]address1;
	input [31:0]address2;
	begin
		write_en =1'b1;
		data_in = {{22{1'b0}}, not_first_time_access, core_id, read_write, stop, address2, {22{1'b0}}, not_first_time_access, core_id, read_write, stop, address1};
		#`CYCLE;
		write_en = 1'b0;
	end
endtask

task read_data;
	input not_first_time_access;
	input [3:0]core_id;
	input [2:0]read_write;
	input [1:0]stop;
	input [31:0]address;
	begin
		read_en = 1'b1;
		#`CYCLE;
		if ({not_first_time_access, core_id, read_write, stop} != access_info) begin
			$display("error! [access_info] expected %h, but got %h\n",
				{not_first_time_access, core_id, read_write, stop}, access_info);
			error=error+1;
		end
		if (address != memory_access) begin
			$display("error! [memory_access] expected %h, but got %h\n",
				address, memory_access);
			error=error+1;
		end
		read_en = 1'b0;
	end
endtask

task start_burst_read;
	begin
		read_en = 1'b1;
		#`CYCLE;
		read_en = 1'b0; // To prevent later commands never read data.
	end
endtask

// Begin of Read and Write at the same time
integer j = 0, k = 0;
initial begin
	@(do_parallel_test);
	#1000;
	if (error) $finish;
	for (j = 0; j < 1024; j = j + 2) begin
		write_data(1'b1, 4'b0001, 3'b001, 2'b00, j, j + 1);
		if (waitrequest) j = j - 2; // Repeat till waitrequest is 0
	end
end

initial begin
	@(do_parallel_test);
	#1000;
	#1100;
    start_burst_read();
	if (error) $finish;
	for (k = 0; k < 1024; k = k + 1) begin
		read_data(1'b1, 4'b0001, 3'b001, 2'b00, k);
		if (~data_valid) k = k - 1; // Repeat till data_valid is 1
	end
	parallel_read_finish = 1;
end
// End of Read and Write at the same time

integer buff_full_idx = 0;
initial begin
	$dumpfile("multibuffer_queue_tb.dump");
	$dumpvars;
	reset();
	rst = 1'b1;
	#`CYCLE;
	rst = 1'b0;
	#`CYCLE;
	write_data(1'b1, 4'b0001, 3'b001, 2'b00, 32'h0000000, 32'hfffffff);
	write_data(1'b1, 4'b0001, 3'b001, 2'b00, 32'h0000300, 32'h0000002);
	write_data(1'b1, 4'b0001, 3'b001, 2'b00, 32'h0000500, 32'hfff33ff);
	write_data(1'b1, 4'b0001, 3'b001, 2'b00, 32'h0000600, 32'hf444fff);
	write_data(1'b1, 4'b0001, 3'b001, 2'b00, 32'h0000600, 32'hf444fff);
	#`CYCLE;
    start_burst_read();
	read_data(1'b1, 4'b0001, 3'b001, 2'b00, 32'h0000000);
	read_data(1'b1, 4'b0001, 3'b001, 2'b00, 32'hfffffff);
	read_data(1'b1, 4'b0001, 3'b001, 2'b00, 32'h0000300);
	read_data(1'b1, 4'b0001, 3'b001, 2'b00, 32'h0000002);
	read_data(1'b1, 4'b0001, 3'b001, 2'b00, 32'h0000500);
	read_data(1'b1, 4'b0001, 3'b001, 2'b00, 32'hfff33ff);
	read_data(1'b1, 4'b0001, 3'b001, 2'b00, 32'h0000600);
	read_data(1'b1, 4'b0001, 3'b001, 2'b00, 32'hf444fff);
	read_data(1'b1, 4'b0001, 3'b001, 2'b00, 32'h0000600);
	read_data(1'b1, 4'b0001, 3'b001, 2'b00, 32'hf444fff);

	// Test write after queue is full
	#100;
	buff_full_idx = -1;
	for (i = 0; i < 1024; i = i + 2) begin
		write_data(1'b1, 4'b0001, 3'b001, 2'b00, i, i + 1);
		if (buff_full_idx == -1 && waitrequest) buff_full_idx = i;
	end
	if (buff_full_idx == -1)
		$display("Buffer was never full in this case.\n");
	else
		$display("Buffer was full at index %h!. This is used for later test.\n", buff_full_idx);

    start_burst_read();
	for (i = 0; i < 1024; i = i + 1) begin
		if (buff_full_idx >= 0 && i > buff_full_idx + 1) begin
			read_data(1'b1, 4'b0001, 3'b001, 2'b00, buff_full_idx + 1);
			if (data_valid) begin
				$display("data_valid should not be true with index %h", i);
				error = error + 1;
			end
		end
		else
			read_data(1'b1, 4'b0001, 3'b001, 2'b00, i);
	end

	do_parallel_test = 1;
	@(parallel_read_finish);

	#500;
	if (error) $display("your design has error!\n");
	else $display("your design is ok!\n");
	$finish;
end

p_multibuffer_queue #(
	.Q_DATA_WIDTH(Q_DATA_WIDTH),
	.M_BUFF_NUM(4),
	.M_BUFF_ADDR_WIDTH(M_BUFF_ADDR_WIDTH),
	.DATA_OUT_WIDTH(INFO_WIDTH + ADDR_WIDTH)
) mutiple_buffer (
	.clk(clk),
	.rst(rst),
	.write_en(write_en),
	.data_in(data_in),
	.waitrequest(waitrequest),
	.read_en(read_en), //original purpose of wairequest is to read next data, so we can regard original waitrequest as read_en
	.data_out({access_info, memory_access}),
	.data_valid(data_valid),
	.full(full),
	.empty(empty),
    .almost_full(almost_full)
	);
endmodule
