CC ?= cc
CFLAGS ?= -std=c11 -O2 -Wall -Wextra -Werror -pedantic

.PHONY: all test clean

all: test_cpu_polling_engine

test_cpu_polling_engine: cpu_polling_engine.c test_cpu_polling_engine.c
	$(CC) $(CFLAGS) -o $@ $^

test: test_cpu_polling_engine
	./test_cpu_polling_engine

clean:
	$(RM) test_cpu_polling_engine
