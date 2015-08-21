// Copyright (c) 2015, Baidu.com, Inc. All Rights Reserved
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef STORAGE_LEVELDB_INCLUDE_COMPACT_STRATEGY_H_
#define STORAGE_LEVELDB_INCLUDE_COMPACT_STRATEGY_H_

#include <stdint.h>
#include <string>
#include "leveldb/iterator.h"

namespace leveldb {

class Slice;
class Iterator;
class InternalKeyComparator;

// the class privides the adjustment functions to
// determine whether user records are drop during
// compaction.
class CompactStrategy {
public:
    virtual ~CompactStrategy() {}

    virtual bool Drop(const Slice& k, uint64_t n) = 0;

    // tera-specific, based on all-level iterators.
    // used in LowLevelScan
    virtual bool ScanDrop(const Slice& k, uint64_t n) = 0;

    virtual bool ScanMergedValue(Iterator* it, std::string* merged_value,
                                 int64_t* merged_num = NULL) = 0;

    virtual bool MergeAtomicOPs(Iterator* it, std::string* merged_value,
                                std::string* merged_key) = 0;

    virtual const char* Name() const = 0;
};


class DummyCompactStrategy : public CompactStrategy {
public:
    virtual ~DummyCompactStrategy() {}

    virtual bool Drop(const Slice& k, uint64_t n) {
        return false;
    }

    virtual bool ScanDrop(const Slice& k, uint64_t n) {
        return false;
    }

    virtual const char* Name() const {
        return "leveldb.DummyCompactStrategy";
    }

    virtual bool MergeAtomicOPs(Iterator* it, std::string* merged_value,
                                std::string* merged_key) {
        return false;
    }

    virtual bool ScanMergedValue(Iterator* it, std::string* merged_value,
                                 int64_t* merged_num) {
        return false;
    }
};

// eche strategy object has its own inner status or context,
// so create anew one when needed.

class CompactStrategyFactory {
public:
    virtual ~CompactStrategyFactory() {}
    virtual CompactStrategy* NewInstance() = 0;
    virtual const char* Name() const = 0;
};

class DummyCompactStrategyFactory : public CompactStrategyFactory {
public:
    virtual CompactStrategy* NewInstance() {
        return new DummyCompactStrategy();
    }
    virtual const char* Name() const {
        return "leveldb.DummyCompactStrategyFactory";
    }
};

} // namespace leveldb


#endif  // STORAGE_LEVELDB_INCLUDE_COMPACT_STRATEGY_H_

