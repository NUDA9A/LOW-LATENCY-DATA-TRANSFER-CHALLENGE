# Standalone build for the fan-out benchmark harness. No external dependencies
# beyond a C++17 compiler and librt (POSIX shared memory).
CXX      ?= g++
CXXFLAGS ?= -std=c++17 -O2 -Wall -Wextra -Iinclude
LDLIBS   ?= -lrt -lpthread

LLDT_MESSAGE_PROFILE ?= raw

ifeq ($(LLDT_MESSAGE_PROFILE),compact)
CPPFLAGS += -DLLDT_MESSAGE_PROFILE_COMPACT=1
else ifeq ($(LLDT_MESSAGE_PROFILE),raw)
else
$(error Invalid LLDT_MESSAGE_PROFILE value: '$(LLDT_MESSAGE_PROFILE)')
endif

BIN := bin
BINARIES := $(BIN)/producer $(BIN)/consumer

HEADERS := $(wildcard include/*.h) $(wildcard include/*.hpp)

.PHONY: all clean test

all: $(BINARIES)

$(BIN):
	mkdir -p $(BIN)

$(BIN)/producer: src/producer.cpp $(HEADERS) | $(BIN)
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) $< -o $@ $(LDLIBS)

$(BIN)/consumer: src/consumer.cpp $(HEADERS) | $(BIN)
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) $< -o $@ $(LDLIBS)

test: $(BIN)/test_harness
	./$(BIN)/test_harness

$(BIN)/test_harness: test/test_harness.cpp $(HEADERS) | $(BIN)
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) $< -o $@ $(LDLIBS)

clean:
	rm -rf $(BIN)
