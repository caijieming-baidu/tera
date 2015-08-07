# LevelDB代码阅读总结
## Write流程
**put或delete流程：**

	1、将kv写入write batch
	2、执行write函数

因此，无论插入或删除，最后都走到write接口；下面就write的流程进行展开。

### 写场景

	write batch对象的数据格式：
	WriteBatch::rep_ :=
		sequence: fixed64
		count: fixed32
		data: record[count]
	record :=
		kTypeValue varstring varstring         |
		kTypeDeletion varstring
	varstring :=
		len: varint32
		data: uint8[len]

**场景1：单个写** 

	1、调用log writer的append操作，将write batch的内容持久化;
	2、将write batch中的每个kv，调用mem的插入接口，写入memtable中;

**场景2：多写并发**

	1、首先将writ batch进队
	2、队首的元素获得调度权
	3、尝试将队列的多个write batch合并，产生一个大的write batch
	4、调用场景1
	5、将本次批量写的所有write bactch线程进行唤醒
	6、若队列上仍然有待处理操作，唤醒队首线程;

#### write的关键对象

**写版本：**

每个写操作都会分配一个序列号，作用：

1、同一个key的更新能定序；

2、作为数据库的逻辑时间戳；

**memtable对象：**

1、内部key=user key+序列号+操作类型

2、key存储格式：
	
	Format of an entry is concatenation of:
		key_size     : varint32 of internal_key.size(): 用户key大小+8
		key bytes    : char[internal_key.size()]
		value_size   : varint32 of value.size()
		value bytes  : char[value.size()]
		
3、导出两个接口：add和get；

4、内部key排序规则：

	（1）用户key升序排列
	（2）同一个用户key，按序列号降序排序

**log writer对象：**

1、数据分块存储，每个块固定32KB，块内存储一个或多个日志记录；

2、每个日志记录的存储格式：

	log record := header + body
	header:= 校验+长度+类型
	类型:= full, first,middle,last
	body:=write batch的rep_内容

3、导出addrecord接口：将write batch的rep_内容，构建日志记录，append到日志文件；

## Get流程
### 读场景：

	1、根据key和序列号，构造内部查key；
	2、从memtable查询key，若找到则返回；
	3、从immemtable查询key，若找到则返回；
	4、从当前的version查找，若找到则返回；

**引用计数：**

在前述3个对象的查询过程中，都释放了memtable的锁，为保证操作过程中，对象不被释放内存，因此，采用引用计数机制，实现对象空间释放由最后一个引用的人释放。引用计数的增减是在数据库的锁保护范围内的。

### verson的get操作：
	1、遍历每一层的key区间，若该层不存在文件，则进入下一个遍历；若找到key则退出。
	2、每一层的遍历过程：
		2.1产生候选区间：
			若是level0，则比较该层每个区间，并记录每个与key有交叠的区间，形成候选区间。对候选区间从新到旧进行排序。
			若该层>level0，则使用二分查找第一个区间的largest key >= key的区间，若key确实落入该区间，则产生候选区间。
		2.2对每个候选区间，执行table cache的Get操作，进行key查询，找到则返回key

### levelDB的cache机制
**table cache**用于缓存sst的索引块，key=sst文件号，value=文件句柄和table句柄

**table句柄**=索引块缓存+cache id

**block cache**用于缓冲sst的数据块，key=cache id+偏移，value=block对象

**block对象：**{非共享key长度+共享key长度+value长度+非共享key+value}列表+重启点列表+重启点个数

sst的文件内部采用分块管理，每个块包含crc和压缩类型，ReadBlock接口用于读取对用的块；具体块分为数据块和索引块，bloom filter块；

#### table cache的查询流程：

	1、若文件没有在table cache中：
		1.1打开文件，创建文件句柄
		1.2读取文件内的footer，在读取文件的索引块到内存中
		1.3将索引块缓存到table cache中
	2、从table cahe中获得文件的table句柄
	3、从索引块查询第一个key，满足key >= target，并获得key对应的数据块的偏移和大小
	4、根据offset和cache id，查询block cache。若数据块不在缓存中：
		4.1 从文件读取数据块
		4.2构建block对象，cache id+偏移作为key，插入block cache中
	5、获得block对象的遍历器，查询第一个key，满足key >= target
	6、根据key与target是否相等，返回结果

#### 通用的cache模型的主要对象：
	
1、**LRUHanle**：LRU cache的元素，包含引用计数，key，hash值，value，权重，链入hash的指针，链入lru链的指针，value的释放器。

2、**HandleTable**：hash表，提供插入，删除，resize操作

3、**LRUCache**：包含互斥锁，hash 表，lru链，容量统计和水位线

4、**shardedLRUCache**：内部默认包含16个LRUCache切片。提供cache的id的分配接口NewId()

## Compact流程
**compact的主要入口：**

MaybeScheduleCompaction=》创建线程执行BGWork-》BackgroundCall-》BackgroundCompaction()

**memtabl的dump：**

	1、压缩immemtale
		1.1分配文件号，创建sst文件
		1.2读取memtable的每个key，value，构建sst文件
		1.3将kv使用key的前缀压缩的方式写入sst的数据块
		1.4若该数据块的大小达到分块水位4KB，则将数据块下刷，并产生一个索引项
		1.5当memtable的kv都遍历完成后，将剩余的数据块写入文件
		1.6将索引块写入文件和文件的footer写入文件
		1.7文件执行sync操作，保证page cache中的数据能实际下盘
		1.8创建table cache，校验sst文件创建成功
		1.9在构建过程中，完成FileMetaData的信息的收集
		1.10根据当前区间的最大最小值，选择将sst文件存放的层次level；构造versionEdit的日志记录
		1.11根据当前version和versionEdit，构造一个新的version（已有的文件保留，将新的文件加入到对应的files层次）
		1.12将当前的versionEdit序列化到manifest文件
		1.13将新的version插入到versionSet中
		1.14压缩退出
**非mirror compact：**

该操作的触发条件：

	1）某个sst文件的读次数达到上水位；
	2）level0的sst文件数量达到上水位；
	3）level>1的sst文件的总大小达到上水位；

压缩流程：

	1、选择待压缩文件：
		1.1若本次压缩是由于某一个level的文件总大小过大触发的，则从中选择一个compact_pointer_指示的下一个待压缩文件作为第一个输入
		1.2若本次压缩是由于某个文件的seek数量达到上水位，则选择该文件作为第一个输入
		注意：level0需要将与该文件区间有交叠的文件都作为输入
		1.3再选择level+1涉及的压缩输入文件
	2、若本次输入只涉及一个文件，则进行构造edit{level层删除该文件，level+1层增加该文件}，将操作写入manifest日志，创建一个新的version插入versionSet。压缩退出
	3、对多个输入流，多路归并排序
		3.1每次对某个kv进行持久化前，先判刑是否有immemtbale非空，若是则实行minor compact
		3.2对于每个产生的kv，若满足一下条件，则丢弃，否则进入sst。条件：
			a）对于同一个key只保留最新修改，丢弃较旧的更新
			b）对于删除操作，若level+2层或更高层次都没有该key，则丢弃删除
		3.3当单个sst大小达到上水位时，切换到新的sst输出
	4、多流归并完成，将level和level+1中参与作为输入的文件添加到edit的删除列表；将level+1新增的文件加入到edit的增加列表，执行LogAndApply，将edit录入manifest的日志中，并产生新的version，添加到versionSet中。

## open流程

	1、创建数据库目录，创建数据锁文件
	2、若current文件不存在，创建manifest文件，创建current文件，指向manifest文件
	3、利用current文件，读取manifest文件
	4、恢复manifest日志的每一个记录，获得删除文件集合和增加文件集合，每一层的压缩指针；log_number,prev_log_number,比较器名字，last_sequence，next_file_number
	5、利用步骤4，构建current version
	6、根据edit中记录的log_number，获得minor compact时崩溃的log
	7、对其日志的每一条记录，加入memtable，若内存压力过大，则触发将memtable持久化到sst的过程
	8、对于恢复log过程中引起的sst变动，使用edit收集信息，并使用LogAndApply接口更新manifest



