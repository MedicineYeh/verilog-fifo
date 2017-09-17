SRCS=$(wildcard *.v)

all : queue
	@echo -e "\tRunning Binary...\n\n"
	@./queue
	@echo -e "\n\n\nPlease run 'gtkwave ./multibuffer_queue_tb.dump' to view the result of timeline."

queue : $(SRCS)
	@echo "  iverilog queue"
	@iverilog $(SRCS) -o queue

