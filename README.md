# MoonBACnet

MoonBit 原生的 **BACnet 对象与属性服务核心**：将建筑设备状态、命令优先级、批量属性查询和变化通知交给可复用的类型化 API。协议核心不依赖 Python、JavaScript 或外部 BACnet 运行时，能在 wasm、wasm-gc、js、native 后端使用。

当前是本地0.1.0首版，模块暂为 `local/moonbacnet`，`private=true`。仓库账号及 Mooncakes namespace 确定后再配置公开地址和发布；目前没有可用的公开安装地址。许可证为 Apache-2.0。

## 用途与生态定位

- **楼宇控制与操作员覆盖**：温度、照明或设备设定值同时受到自动策略与人工命令影响。用16级 priority array 保留各方意图，Null 释放当前槽，恢复较低优先级或 relinquish default，避免把“释放”误写成零。
- **能源与设备管理网关**：通过 Who-Is/I-Am 发现设备，枚举 Object_List，以 ReadPropertyMultiple 读取多个测点、单位和名称；单个未知对象/属性返回独立错误，不丢弃其余成功数据。
- **运行状态监测**：按累计变化阈值观察模拟量，以及二进制故障状态/Status_Flags；接收初始快照、变化通知和有限期订阅，减少无变化轮询。这里使用 COV，不包含完整的事件告警确认服务。

上述三类场景均有可运行的本地例子。现有 MoonBit IEC104、Modbus 包和本地 MoonAMQP1 分别处理其他标准的点命令或消息传输；BACnet 增补对象标识、属性数组、命令优先级、发现和 COV 的不同语义。本轮 `bacnet/BACnet/bvlc/npdu/bacpypes` 检索未发现同核心成熟 Mooncakes 包；这是有范围的查重结果，不是对整个生态绝无相关实现的保证。

## 安装与运行

已验证 moonc **v0.10.16**、Moon0.1.20261016；原生目标需要 C 编译器，JS 示例需要 Node.js。本库可只用 MoonBit 构建；Python3.11 和 BACpypes3 仅用于独立互操作测试。

取得源码目录后运行：

```sh
moon check --target all --deny-warn
moon build --target all --deny-warn
moon test --target all --deny-warn
moon run examples/hvac --target native --deny-warn
moon run examples/energy --target native --deny-warn
moon run examples/monitoring --target js --deny-warn
moon run examples/scale --target native --deny-warn
```

Windows 已提供当前官方编译器的路径适配入口。若工具链无法处理扩展路径 `\\?\`，把命令中的 `moon` 换成 `& .\tools\windows\moon.ps1`，例如：

```powershell
& .\tools\windows\moon.ps1 test --target all --deny-warn
& .\tools\windows\moon.ps1 run examples/hvac --target native --deny-warn
```

脚本只在本进程为官方 moonc/moonfmt/mooninfo 子进程规范化参数路径，不改变全局环境。依赖 `moonbitlang/async@0.22.5` 只被原生 CLI 的文件及 stdio 宿主导入，类型、服务和设备核心均不依赖它。

## 最小使用样例

项目内的消费包使用 `moon.pkg`：

```moonbit
import { "local/moonbacnet" @bac, }
pkgtype(kind: "executable")
```

以下过程对应可运行的 `examples/hvac`：

```moonbit
fn main raise {
  let device = @bac.Device::new(42, "room-controller", 999U)
  let id = @bac.ObjectId::new(2, 1) // analog-value
  device.add_point(id, "setpoint", Analog, Real(19.0F), commandable=true)
  let server = @bac.Server::new(device)
  let client = @bac.Client::new()
  let body = @bac.encode_write_property({
    reference: { object: id, property: 85U, index: None },
    value: [Application(Real(23.0F))], priority: Some(8),
  })
  let tx = client.start("device", 15, body, 0UL)
  let reply = server.datagram(tx.bytes, "client", 0UL).unwrap()
  assert_true(client.receive("device", @bac.decode_datagram(reply), 0UL)
    is Some(Completed(SimpleAck(_, 15))))
  assert_eq(device.active_priority(id), Some(8))
}
```

宿主负责把 tx.bytes 经可靠的对端映射交给 UDP 等传输，把响应和单调递增的秒数送回核心；例子在内存中传递完整 BACnet/IP datagram。`peer` 是对端身份键，不提供认证。真实集成必须提供访问控制、可信网络和稳定地址映射，核心不会把 priority 当作权限系统。

## API 与功能边界

| 层次 | 已实现 | 首版边界 |
| --- | --- | --- |
| 应用值 | null/bool/uint32/int32/REAL/DOUBLE/octet/string/bits/enum/date/time/object-id，精确位模式，嵌套context | 字符串仅encoding0 UTF-8；日期使用1900年偏移和协议通配字节，不提供日历运算 |
| 标签 | 扩展tag、8/16/32位长度、opening/closing、严格截断/计数/深度检查 | 未知application tag明确拒绝；编码规范化整数宽度，不保留原输入的非最短形式 |
| 网络报文 | IPv4 BVLC 原始单播/广播、forwarded、distribute、result、foreign-register；NPDU路由字段 | 只编解码相关包；没有BBMD表、外来设备注册管理、路由器、MS/TP、IPv6或BACnet/SC |
| APDU | 未分段confirmed/unconfirmed、simple/complex ACK、error/reject/abort | 分段及SegmentACK明确拒绝；设备宿主最多1476字节APDU，按请求方最大长度返回有界abort |
| 服务 | Who-Is/I-Am、ReadProperty、WriteProperty、ReadPropertyMultiple、SubscribeCOV、unconfirmed COV notification | RPM支持all(8)展开，required/optional宏未实现；不支持WritePropertyMultiple等其他服务 |
| 属性库 | 对象ID/名称唯一、Object_List/Property_List、数组索引、标量及只读自定义数组、类型与预算检查 | 索引0为数组长度，None为整体；远端数组及compound写入未实现；对象集合不经网络创建 |
| 测点 | analog/binary/multi-state input/output/value，类型域、Status_Flags、Out_Of_Service | 为明确子集对象模型，未实现标准对象的所有必备属性/行为；不是完整可认证设备profile |
| 控制 |16级在途命令槽、默认priority16、Null释放、relinquish default、域检查 | priority6保留，网络写入拒绝；未实现输出最小开/关时间及优先级6内部计时；默认值由宿主API设置 |
| COV | 初始快照、累计模拟量阈值、二进制/状态变化、续期/取消/过期、原子poll | 只接受unconfirmed通知订阅；0 lifetime代表不定期，取消为两个可选字段均缺失；无通知持久重发 |
| 事务 | 按peer关联invoke/service/reference、轮转ID、超时/定次重试/取消 | 无网络socket；重复写入的业务幂等性仍由宿主决定；RPM客户端校验结构与service，不实现完整请求结果集合证明 |

通用 Tag/服务codec能表示设备profile之外的数据。`Device.add_point` 检查标准测点kind与值域；输出对象必须启用命令优先级，输入对象不得设为commandable。网络权限由注册时的 writable 及 commandable 属性决定。`Device.update` 是可信宿主入口，维护四位状态标志与 Out_Of_Service 一致性；不实现输入点脱机模式下的网络写入扩展。

ReadPropertyACK、RPM及COV的constructed value可为空，以表示真实空数组；这与必需字段缺失不同。存储与返回值均建立快照，调用者修改数组不会改写已保存的属性或COV基线。

## 时钟、重传与宿主责任

`Client.start/receive/poll`、`Server.handle/datagram/notifications` 和 `CovManager` 使用宿主提供的单调秒数；时间倒退和截止溢出明确报错。Client.poll 返回 Retry 或 TimedOut，重复调用不会重复发同一到期事件；宿主负责发送返回的字节。客户端ID轮转且不覆盖同peer在途ID。

Server缓存同peer/invoke的已完成响应30秒，相同请求逐字节重传复用响应，避免再次写入或续期。相同invoke但请求内容变化被视为新事务；缓存数量/字节均受限，会淘汰最旧条目。因此缓存不是持久exactly-once保证，宿主应避免在缓存期内复用相同invoke发送不同业务含义的相同报文。广播confirmed请求被忽略；设备宿主不接受forwarded或routed数据，也不提供BBMD信任判断。

`notifications(now)` 返回通知后推进基线，由宿主决定实际发送和接收策略。无时钟线程、自动重连或后台队列；对象只支持串行驱动，不保证并发修改安全。

## 预算与复杂度

默认 `Limits`：65535逻辑字节、8192 tag节点、32层嵌套、256对象、每对象256属性（包括计算属性）、128订阅、128在途事务/响应缓存条目。可调整，嵌套上限128。存储属性聚合wire字节、待发事务字节、单批通知和RPM结果各自有预算；缓存预算为2×max_bytes+256，额外peer地址限256 UTF-8字节。这些不是整个进程RSS的精确上限。

设N为wire字节、V为tag节点、D为嵌套深度，标签编解码O(N+V)，递归栈O(D)；Writer直接写同一输出缓冲，不反复拼接父容器。文本body和规范化快照另有线性副本。属性查找O(O+P+X)，O为对象数、P为对象属性数、X为返回的属性数据规模；每次命令选择扫描固定16槽。RPM按实际展开属性数处理，不按数值ID跨度循环。COV轮询最坏O(S·(O+P)+B)，S为订阅数、B为产生的编码字节。事务匹配/取消与缓存查找O(T)，invoke分配最多O(256·T)，批量数组删除/缓存淘汰最坏O(T²)，T默认限128；当前有界规模下优先保留直接可验证的数据结构，尚未做速度基准证明需要更复杂索引。

`examples/scale` 验证64测点、32订阅、4096次写入及4096次读取、2048次变化通知；写入/回复流量143360字节。它是有界正确性负载，不是速度或内存基准。

## 独立验证与 CLI

```sh
moon build --target native --deny-warn
python -m pip install --target _local/oracle -r scripts/requirements-interop.txt
python scripts/interop.py
moon run cmd/main --target native -- tags INPUT.bin NEW_OUTPUT.bin
moon run cmd/main --target native -- rp INPUT.bin NEW_OUTPUT.bin
```

CLI支持 tags、apdu、bvlc、npdu、rp、rp-ack、wp、rpm、rpm-ack、cov-sub、cov、whois、iam；输入最多65535字节，输出路径必须尚不存在。`peer` 输入逐行十六进制BACnet/IP datagram，输出对应回复或`-`；保持一个示例设备，固定逻辑时刻0。它用于互操作验证，不是有真实时钟或UDP接入的设备服务。

固定BACpypes3 **0.0.110**，已验证23组类型和13组服务/报文向量双向编码，以及11次真实Python实现对持续MoonBit宿主的请求：发现、优先级写入/读取/释放、RPM、错误、订阅/取消。使用stdio，没有连接外部设备或真实UDP网络，不构成BTL认证、完整标准符合性或厂商兼容认证。

本地严格检查、构建、四后端各52个测试、格式和接口快照已通过。CI配置覆盖上述流程、四个示例、独立oracle、打包与Git/ZIP内容检查；尚未执行公开GitHub CI。来源与AI辅助范围见 [THIRD_PARTY.md](THIRD_PARTY.md)，主要公共API快照见 `pkg.generated.mbti`。

规范与参考：[BACnet委员会](https://bacnet.org/about-bacnet/)、[BACpypes3文档](https://bacpypes3.readthedocs.io/en/latest/)、[BACpypes3源码](https://github.com/JoelBender/BACpypes3)、[固定版本元数据](https://pypi.org/project/bacpypes3/0.0.110/)。
