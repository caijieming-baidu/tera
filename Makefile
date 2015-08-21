include depends.mk

# OPT ?= -O2 -DNDEBUG       # (A) Production use (optimized mode)
OPT ?= -g2 -Wall -Werror        # (B) Debug mode, w/ full line-level debugging symbols
# OPT ?= -O2 -g2 -DNDEBUG   # (C) Profiling mode: opt, but w/debugging symbols

CC = cc
CXX = g++

SHARED_CFLAGS = -fPIC
SHARED_LDFLAGS = -shared -Wl,-soname -Wl,

INCPATH += -I./src -I./include -I./src/leveldb/include -I./src/leveldb \
		   -I./src/sdk/java/native-src $(DEPS_INCPATH) 
CFLAGS += $(OPT) $(SHARED_CFLAGS) $(INCPATH)
CXXFLAGS += $(OPT) $(SHARED_CFLAGS) $(INCPATH)
LDFLAGS += -rdynamic $(DEPS_LDPATH) $(DEPS_LDFLAGS) -lpthread -lrt -lz -ldl

PROTO_FILES := $(wildcard src/proto/*.proto)
PROTO_OUT_CC := $(PROTO_FILES:.proto=.pb.cc)
PROTO_OUT_H := $(PROTO_FILES:.proto=.pb.h)

MASTER_SRC := $(wildcard src/master/*.cc)
TABLETNODE_SRC := $(wildcard src/tabletnode/*.cc)
IO_SRC := $(wildcard src/io/*.cc)
SDK_SRC := $(wildcard src/sdk/*.cc)
PROTO_SRC := $(filter-out %.pb.cc, $(wildcard src/proto/*.cc)) $(PROTO_OUT_CC)
JNI_TERA_SRC := $(wildcard src/sdk/java/native-src/*.cc)
VERSION_SRC := src/version.cc
OTHER_SRC := $(wildcard src/zk/*.cc) $(wildcard src/utils/*.cc) $(VERSION_SRC) \
	     src/tera_flags.cc
COMMON_SRC := $(wildcard src/common/base/*.cc) $(wildcard src/common/net/*.cc) \
              $(wildcard src/common/file/*.cc) $(wildcard src/common/file/recordio/*.cc)
SERVER_SRC := src/tera_main.cc src/tera_entry.cc
CLIENT_SRC := src/teracli_main.cc
MONITOR_SRC := src/monitor/teramo_main.cc
MARK_SRC := src/benchmark/mark.cc src/benchmark/mark_main.cc

MASTER_OBJ := $(MASTER_SRC:.cc=.o)
TABLETNODE_OBJ := $(TABLETNODE_SRC:.cc=.o)
IO_OBJ := $(IO_SRC:.cc=.o)
SDK_OBJ := $(SDK_SRC:.cc=.o)
PROTO_OBJ := $(PROTO_SRC:.cc=.o)
JNI_TERA_OBJ := $(JNI_TERA_SRC:.cc=.o)
OTHER_OBJ := $(OTHER_SRC:.cc=.o)
COMMON_OBJ := $(COMMON_SRC:.cc=.o)
SERVER_OBJ := $(SERVER_SRC:.cc=.o)
CLIENT_OBJ := $(CLIENT_SRC:.cc=.o)
MONITOR_OBJ := $(MONITOR_SRC:.cc=.o)
MARK_OBJ := $(MARK_SRC:.cc=.o)
ALL_OBJ := $(MASTER_OBJ) $(TABLETNODE_OBJ) $(IO_OBJ) $(SDK_OBJ) $(PROTO_OBJ) \
           $(JNI_TERA_OBJ) $(OTHER_OBJ) $(COMMON_OBJ) $(SERVER_OBJ) $(CLIENT_OBJ) \
           $(MONITOR_OBJ) $(MARK_OBJ)
LEVELDB_LIB := src/leveldb/libleveldb.a

PROGRAM = tera_main teracli teramo
LIBRARY = libtera.a
JNILIBRARY = libjni_tera.so
BENCHMARK = tera_bench tera_mark

.PHONY: all clean cleanall test

all: $(PROGRAM) $(LIBRARY) $(JNILIBRARY) $(BENCHMARK)
	mkdir -p build/include build/lib build/bin build/log build/benchmark
	cp $(PROGRAM) build/bin
	cp $(LIBRARY) $(JNILIBRARY) build/lib
	cp src/leveldb/tera_bench .
	cp -r benchmark/*.sh $(BENCHMARK) build/benchmark
	cp src/sdk/tera.h build/include
	cp -r conf build
	echo 'Done'

test:
	echo "No test now!"
	
clean:
	rm -rf $(ALL_OBJ) $(PROTO_OUT_CC) $(PROTO_OUT_H)
	$(MAKE) clean -C src/leveldb
	rm -rf $(PROGRAM) $(LIBRARY) $(JNILIBRARY) $(BENCHMARK)

cleanall:
	$(MAKE) clean
	rm -rf build

tera_main: $(SERVER_OBJ) $(LEVELDB_LIB) $(MASTER_OBJ) $(TABLETNODE_OBJ) \
           $(IO_OBJ) $(SDK_OBJ) $(PROTO_OBJ) $(OTHER_OBJ) $(COMMON_OBJ)
	$(CXX) -o $@ $(SERVER_OBJ) $(MASTER_OBJ) $(TABLETNODE_OBJ) $(IO_OBJ) $(SDK_OBJ) \
	$(PROTO_OBJ) $(OTHER_OBJ) $(COMMON_OBJ) $(LEVELDB_LIB) $(LDFLAGS)

libtera.a: $(SDK_OBJ) $(PROTO_OBJ) $(OTHER_OBJ) $(COMMON_OBJ)
	$(AR) -rs $@ $(SDK_OBJ) $(PROTO_OBJ) $(OTHER_OBJ) $(COMMON_OBJ)

teracli: $(CLIENT_OBJ) $(LIBRARY)
	$(CXX) -o $@ $(CLIENT_OBJ) $(LIBRARY) $(LDFLAGS)

teramo: $(MONITOR_OBJ) $(LIBRARY)
	$(CXX) -o $@ $(MONITOR_OBJ) $(LIBRARY) $(LDFLAGS)

tera_mark: $(MARK_OBJ) $(LIBRARY) $(LEVELDB_LIB)
	$(CXX) -o $@ $(MARK_OBJ) $(LIBRARY) $(LEVELDB_LIB) $(LDFLAGS)
 
libjni_tera.so: $(JNI_TERA_OBJ) $(LIBRARY) 
	$(CXX) -shared $(JNI_TERA_OBJ) -Xlinker "-(" $(LIBRARY) $(LDFLAGS) -Xlinker "-)" -o $@ 

src/leveldb/libleveldb.a: FORCE
	$(MAKE) -C src/leveldb

tera_bench:

$(ALL_OBJ): %.o: %.cc $(PROTO_OUT_H)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(VERSION_SRC): FORCE
	sh build_version.sh

.PHONY: FORCE
FORCE:

.PHONY: proto
proto: $(PROTO_OUT_CC) $(PROTO_OUT_H)
 
%.pb.cc %.pb.h: %.proto
	$(PROTOC) --proto_path=./src/proto/ --proto_path=$(PROTOBUF_INCDIR) \
                  --proto_path=$(SOFA_PBRPC_INCDIR) \
                  --cpp_out=./src/proto/ $< 
