# BACnet 标准范围与可复现交互

目标固定为 ANSI/ASHRAE 135-2020（Protocol_Version 1、Protocol_Revision 22）及适用勘误。最终验收覆盖最低设备要求、所声明的十一种对象及服务的全部必需和条件必需行为。版本基线见 [BACnet 委员会](https://bacnet.org/updates/)，符合性说明采用 [PICS](https://bacnet.org/conformance-pics/) 的对象、服务和角色口径。

本页描述 0.2.0 之后的源码增量。已发布的 0.2.0 提供此前的接口与测试基线。使用本目录源码复现下列新增交互。

## 构建设备与配置宿主

`Device::new_standard(instance, name, vendor, port)` 初始化 Device 的身份、版本、事务参数与地址绑定属性，以及一个普通 IPv4 Network Port。地址、掩码、网关和 UDP 端口由调用者提供；UDP 示例用实际绑定的端口初始化，stdio 测试用例使用合成端口描述。`Device::new` 继续提供基础注册表构建入口。

设备能力位随当前对象集合生成。服务能力位标记可执行的 ConfirmedCOVNotification、SubscribeCOV、ReadProperty、ReadPropertyMultiple、WriteProperty、UnconfirmedCOVNotification、Who-Has 和 Who-Is。由设备发起的 I-Am／I-Have 不置为可执行服务。Device 的 Database_Revision 随对象、属性和名称的结构变化推进。构造函数提供协议身份，完整符合性仍按本文末尾的条款验收完成情况判断。

九种测点类型提供 Event_State；Binary Input／Output 提供 Polarity；命令对象提供动态 Current_Command_Priority。Present_Value、Status_Flags 和 Out_Of_Service 的关系经写入路径校验。宿主负责真实物理输入输出和 Polarity 对硬件信号的映射。

## 标准请求与预期响应

下面的服务字段表示线上的 BACnet 请求。例子中的厂商号 999 为合成测试参数。测试逐项检查编码类型和响应后的设备状态。

### 对象发现

输入 Who-Has，objectName=room-setpoint。当该名称存在且设备实例处于可选范围内时，返回 I-Have，deviceIdentifier=device,42、objectIdentifier=analog-value,1、objectName=room-setpoint。按 Object_Identifier 查询使用同一匹配规则。名称不存在或设备不在范围内时不产生 I-Have。缺失范围一端、倒置范围、错误选择类型及多余字段均被拒绝。

对应入口为 `encode_who_has`、`decode_who_has`、`encode_i_have`、`decode_i_have`，服务端由 `Server::handle/datagram` 驱动。

### 通配设备与端口读取

输入 ReadProperty(device,4194303,Object_Identifier)。响应中的对象标识和属性值均为实际 device,42；客户端接受这一标准通配响应，同时拒绝返回普通测点对象的伪匹配。RPM 对 Object_Identifier 的通配读取也回显实际设备标识。

读取 device,42 的 Protocol_Revision 得到 Unsigned(22)。读取 network-port,1 的 Network_Type 得到 Enumerated(5)，读取 BACnet_IP_UDP_Port 得到实际配置端口。读取 Object_List[0] 返回包括 Device 和 Network Port 的对象数。

### RPM 选择器与部分错误

对 analog-value,1 请求 Present_Value、Priority_Array[0] 和未知属性 9999。默认设定值为 19 时，ComplexACK 中分别得到 REAL(19)、Unsigned(16) 和 PROPERTY／UNKNOWN_PROPERTY。错误只作用于该属性。

ALL(8) 展开当前存在的属性；REQUIRED(105) 根据对象类型与命令／COV 等条件分类；OPTIONAL(80) 返回存在的可选或自定义属性。没有匹配可选属性时，返回该选择器的属性错误。数组索引继续按标准表示整体、数量或单元素。

`correlate_read_multiple` 和 `correlate_read_batches` 对显式属性清单核对对象、属性与索引顺序。选择器的展开结果使用 `decode_multiple_ack` 读取。

### 脱机输入与命令恢复

输入对象在 Out_Of_Service=false 时，写 Present_Value 返回 WRITE_ACCESS_DENIED。先写 Out_Of_Service=true 获得 SimpleACK，再写合法测量值，读回更新后的值，Status_Flags 的对应位为 true。错误数据类型或值域不会改变原状态。

命令对象按优先级 8 写入 23、按优先级 16 写入 21 时，Present_Value 为 23，Current_Command_Priority 为 Unsigned(8)。以 Null 释放优先级 8 后回到 21。释放全部槽后回到 Relinquish_Default，当前优先级为 Null。Relinquish_Default 可通过 WriteProperty 设置并进行类型校验。Object_Name 的网络改名校验同设备内名称唯一性。

### 确认型与非确认型 COV

SubscribeCOV(process=7, object=analog-value,1, confirmed=true, lifetime=5) 获得 SimpleACK。宿主调用 `Server::confirmed_notifications(now)` 获取初始 ConfirmedCOVNotification 的字节；通过传输发送，并把收到的 ACK 交给 `handle/datagram`。未确认时，按默认 3 秒间隔重试，最多重试 2 次。重试保留 invoke ID 和完整载荷。确认后清除待结算事务，下一次变化形成新的通知。

`notification_deadline` 提供重试期限。`take_notifications` 读取已接受的通知；确认请求的重复帧由响应缓存去重。不同 peer 或错误服务的 ACK 不完成原事务。接收队列、在途数和字节预算有界。

未确认通知单独由 `Server::notifications(now)` 输出，保持现有入口。续期更新生命周期并安排初始快照；取消和到期会在驱动确认发送器时清除有关在途通知。新一批通知无法进入发送预算时撤销该批已启动事务，保留待发快照供后续重试。

### 分段请求与恢复

设备声明 noSegmentation。收到具有合法分段头的确认请求时，返回 Abort，server=true、invoke ID 与请求一致、reason=segmentation-not-supported(4)。下一条合法请求仍可正常处理。超过声明响应 APDU 上限时沿用有界 Abort 处理。分段重组为后续可选能力。

## 复现

```sh
moon check --target all --deny-warn
moon build --target all --deny-warn
moon test --target all --deny-warn
moon run examples/standard_exchange --target native --deny-warn
moon run examples/standard_exchange --target wasm-gc --deny-warn
python -m pip install --target _local/oracle -r scripts/requirements-interop.txt
python scripts/interop.py
python scripts/udp_interop.py
```

Windows 可用项目的 `tools/windows/moon.ps1` 替换 moon 命令。标准示例打印 Who-Has、通配设备读取、RPM 部分失败和 COV 重传确认的实际结果。当前源码通过四后端各 79 项测试、七个运行示例；标准示例在 Native 与 Wasm-GC 均通过。独立 stdio 对照覆盖 23 组类型、16 组服务向量与 28 次请求。UDP 脚本发送 20 个输入，故意丢弃初始确认通知的 ACK，比较原帧和重传帧，再确认、接收变化通知、取消订阅并检查分段 Abort 后的正常发现。

## 最终验收与当前余项

最终对象范围包括 Device、普通 IPv4 Network Port，以及 Analog／Binary／Multi-state 的 Input、Output、Value。服务发起与执行方向、可选属性和触发的条件必需行为逐项对照固定版本验证。最终交付还包括经过逐条确认的 PICS、条款与测试入口索引、独立标准请求及预期响应记录。

当前增量已经把上述交互接入正常报文路径。Network Port 配置修改与生效、各对象可选功能触发的完整条件行为、运行参数可配置性和生产设备互操作仍需逐条验收。现有普通 IPv4 宿主面向本地端口，BBMD、外来设备、路由、MS/TP、IPv6、BACnet/SC 与新增对象或服务按各自适用义务扩展。全部最终条目通过后发布符合该声明范围的正式版本。
