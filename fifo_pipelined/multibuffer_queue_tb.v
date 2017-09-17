//`default_nettype none
`timescale 1ns/10ps
`define CYCLE 20

module multibuffer_queue_tb;

parameter Q_DATA_WIDTH = 128;
parameter INFO_WIDTH = 10;
parameter ADDR_WIDTH = 32;
parameter DATA_OUT_WIDTH = 64;
parameter M_BUFF_ADDR_WIDTH = 10;

parameter SMALL_LOOP_SIZE = 32;
parameter BIG_LOOP_SIZE = 1024;

parameter REPEATED_NUMBER = 16;

reg clk;
reg rst;
reg write_en;
reg [Q_DATA_WIDTH-1:0] data_in;
wire waitrequest;
reg read_en;
wire[DATA_OUT_WIDTH-1:0] data_out;
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

reg[Q_DATA_WIDTH-1:0] write_task_buff;

task reset;
	begin
		write_en = 1'b0;
		read_en = 1'b0;
		data_in = 'd0;
		write_task_buff <= 'd0;
	end
endtask

integer write_offset = 0;
task write_data;
	input[DATA_OUT_WIDTH-1:0] payload;
	integer write_i;
	begin
		for (write_i = 0; write_i < DATA_OUT_WIDTH; write_i = write_i + 1) begin
			write_task_buff[write_offset] = payload[write_i];
			write_offset = write_offset + 1;
			if (write_offset >= Q_DATA_WIDTH) begin
				write_offset = write_offset % Q_DATA_WIDTH;
				write_en =1'b1;
				data_in = write_task_buff;
				#`CYCLE;
				write_en =1'b0;
			end
		end
	end
endtask

task flush_write_task_buff;
	integer write_i;
	integer times;
	begin
		if (!waitrequest && write_offset != 0) begin
			times = $ceil((Q_DATA_WIDTH-write_offset)/(DATA_OUT_WIDTH));
			for (write_i = 0; write_i <= times; write_i = write_i + 1) begin
				write_data(0);
			end
		end
	end
endtask

task flush_read_buff;
	begin
		read_en = 1'b1;
		while (!empty) #`CYCLE;
		read_en = 1'b0;
	end
endtask

task read_data;
	input[DATA_OUT_WIDTH-1:0] payload;
	begin
		read_en = 1'b1;
		#`CYCLE;
		if (data_valid) begin
			if (payload != data_out) begin
				$display("error! read expected %h, but got %h\n",
					payload, data_out);
				error=error+1;
			end
		end
		else begin
			$display("error! data_valid was not high at payload == %h!", payload);
			error=error+1;
		end
		read_en = 1'b0;
	end
endtask

task start_burst_read;
	begin
		read_en = 1'b1;
		#`CYCLE;
		#`CYCLE;
		read_en = 1'b0; // To prevent later commands never read data.
	end
endtask

task check_control_signals;
	begin
		if (!empty || full || almost_full || waitrequest) begin
			error = error + 1;
			$display("Error: One of the control signal was not right");
		end
	end
endtask

task test_basic;
	integer r_array[0:31];
	begin
		// Some random read write test
		$display("=== Testing Basic Operations ===");
		for (i = 0; i < SMALL_LOOP_SIZE; i = i + 1) begin
			r_array[i] = $random;
		end

		for (i = 0; i < SMALL_LOOP_SIZE; i = i + 1) begin
			write_data(r_array[i]);
		end
		flush_write_task_buff();

		if (empty) begin
			error = error + 1;
			$display("Error: empty is still high");
		end

		#`CYCLE;
		start_burst_read();
		for (i = 0; i < SMALL_LOOP_SIZE; i = i + 1) begin
			read_data(r_array[i]);
		end

		$display("=== End of Testing Basic Operations ===");
		#100;
		end
endtask

task test_abort;
	begin
		$display("=== Testing Aborting Read Operation ===");
		// Test aborting read
		for (i = 0; i < SMALL_LOOP_SIZE; i = i + 1) begin
			write_data(i);
			if (buff_full_idx == -1 && waitrequest) buff_full_idx = i;
		end
		flush_write_task_buff();

		#100;
		// Test aborting in the middle. This should not read any data out of the queue.
		for (i = 0; i < SMALL_LOOP_SIZE; i = i + 1) begin
			#`CYCLE;
			read_en = 1'b1;
			if (data_valid) begin
				error = error + 1;
			end
			#`CYCLE;
			read_en = 1'b0;
			if (data_valid) begin
				error = error + 1;
			end

		end
		if (error)
			$display("error: data_valid was true in the middle of test...");
		#100;

		for (i = 0; i < SMALL_LOOP_SIZE; i = i + 1) begin
			start_burst_read();
			read_data(i);
			if (!data_valid) begin
				$display("error: data_valid was not true with index %h", i);
				error = error + 1;
			end
			#`CYCLE;
		end
		#100;
		$display("=== End of Testing Aborting Read Operation ===");
		end
endtask

task test_full_queue;
	begin
		$display("=== Testing Read/Write After A Full Queue ===");
		// Test write after queue is full
		#100;
		buff_full_idx = -1;
		for (i = 0; i < BIG_LOOP_SIZE; i = i + 1) begin
			if (!waitrequest) write_data(i);
			if (buff_full_idx == -1 && waitrequest) begin
				// If there are some remaining bytes, the last one was not successfully written.
				if (write_offset != 0) buff_full_idx = i - 1;
				else buff_full_idx = i;
			end
		end
		if (buff_full_idx >= 0 && (!full || !almost_full)) begin
			error = error + 1;
			$display("Error: full is low or almost_full is low");
		end

		if (buff_full_idx == -1)
			$display("\t[Notice] Buffer was never full in this case.");
		else
			$display("\t[Notice] Buffer was full at index %h!. This is used for later test.", buff_full_idx);

		start_burst_read();
		for (i = 0; i < BIG_LOOP_SIZE; i = i + 1) begin
			if (buff_full_idx >= 0 && i == buff_full_idx + 1) begin
				read_en = 1'b1;
				#`CYCLE read_en = 1'b0;
				if (write_offset == 0 && data_valid) begin
					$display("data_valid should not be true with index %h", i);
					error = error + 1;
				end
			end
			else if (buff_full_idx >= 0 && i > buff_full_idx + 1) begin
				read_en = 1'b1;
				#`CYCLE read_en = 1'b0;
				if (data_valid) begin
					$display("data_valid should not be true with index %h", i);
					error = error + 1;
				end
			end
			else begin
				read_data(i);
			end
		end
		#100;
		$display("=== End of Testing Read/Write After A Full Queue ===");
		end
endtask

task test_parallel_rw;
	begin
		$display("=== Testing Read/Write Concurrently ===");
		parallel_read_finish = 0;
		do_parallel_test = 1;
		#100;
		do_parallel_test = 0;
		@(parallel_read_finish);
		$display("=== End of Testing Read/Write Concurrently ===");
		end
endtask

// Begin of Read and Write at the same time
integer j = 0, k = 0;
initial begin
	while (1) begin
		@(do_parallel_test);
		#1000;
		if (error) $finish;
		for (j = 0; j < BIG_LOOP_SIZE; j = j + 1) begin
			if (!waitrequest) write_data(j);
			while (waitrequest) #`CYCLE ;//j = j - 1; // Repeat till waitrequest is 0
		end
		flush_write_task_buff();
		#100;
	end
end

initial begin
	while (1) begin
		@(do_parallel_test);
		#1000;
		#1100;
		start_burst_read();
		if (error) $finish;
		for (k = 0; k < BIG_LOOP_SIZE; k = k + 1) begin
			if (!empty) read_data(k);
			if (~data_valid) #`CYCLE k = k - 1; // Repeat till data_valid is 1
		end
		flush_read_buff();
		#100;
		parallel_read_finish = 1;
	end
end
// End of Read and Write at the same time

integer buff_full_idx = 0;
integer rloop_i = 0, rloop = 0;
initial begin
	$dumpfile("multibuffer_queue_tb.dump");
	$dumpvars;
	reset();
	rst = 1'b1;
	#100;
	rst = 1'b0;
	#`CYCLE;
	check_control_signals();

	for (rloop = 0; rloop < 8; rloop = rloop + 1) begin
		if (error == 0) begin
			for (rloop_i = 0; rloop_i < REPEATED_NUMBER; rloop_i = rloop_i + 1) begin
				test_basic();
				check_control_signals();
			end
		end
		if (error == 0) begin
			for (rloop_i = 0; rloop_i < REPEATED_NUMBER; rloop_i = rloop_i + 1) begin
				test_abort();
				check_control_signals();
			end
		end
		if (error == 0) begin
			for (rloop_i = 0; rloop_i < REPEATED_NUMBER; rloop_i = rloop_i + 1) begin
				test_full_queue();
				check_control_signals();
			end
		end
		if (error == 0) begin
			for (rloop_i = 0; rloop_i < REPEATED_NUMBER; rloop_i = rloop_i + 1) begin
				test_parallel_rw();
				check_control_signals();
			end
		end
	end

	// if (write_offset != 0) $display("\n\tWarning: some data (in testbench) are not written to queue.");
	#500;
	if (error) $display("\n\tYour design has error!\n");
	else $display("\n\tPassed!\n");
	$finish;
end

multibuffer_queue #(
	.Q_DATA_WIDTH(Q_DATA_WIDTH),
	.M_BUFF_NUM(4),
	.M_BUFF_ADDR_WIDTH(M_BUFF_ADDR_WIDTH),
	.DATA_OUT_WIDTH(DATA_OUT_WIDTH)
) mutiple_buffer (
	.clk(clk),
	.rst(rst),
	.write_en(write_en),
	.data_in(data_in),
	.waitrequest(waitrequest),
	.read_en(read_en), //original purpose of wairequest is to read next data, so we can regard original waitrequest as read_en
	.data_out(data_out),
	.data_valid(data_valid),
	.full(full),
	.empty(empty),
	.almost_full(almost_full)
	);
endmodule
