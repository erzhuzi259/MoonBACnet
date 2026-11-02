# MoonBACnet 十一月功能扩展

设备接入程序不仅要读写字节，还要保留对象标识、属性数组、命令意图、变化订阅和请求响应的语义。项目把这些能力做成可嵌入的 MoonBit 核心，供设备网关、集成测试和运维工具复用；楼宇自动化是主要应用，其他场景仍须是实际采用 BACnet 的设备，不能据此宣称适配任意物联网协议。

## 1. 设备发现与冲突目录

`DiscoveryDirectory`：收集已解码 I-Am，按设备身份保留 peer、能力、首次/最近发现时间；重复刷新不新增记录，不同地址或能力冲突明确拒绝，支持按龄过期和显式忘记。目录不扫描网络、不认证设备。

复杂度与代价：每次观察/忘记 O(D)，过期 O(D)，D 有容量上限；时间差避免截止相加溢出，返回独立目录副本。

## 2. 命令仲裁可解释快照

`Device::command_snapshot`：返回有效值、生效优先级、relinquish default 及全部占用槽，解释操作员覆盖了哪条自动策略。释放高优先级命令后可观察低优先级意图恢复，快照不提供写入权限。

复杂度与代价：对象查找后只扫描固定16槽；输出为独立快照，不修改设备和历史快照。

## 3. Native UDP 接入与独立网络验证

`cmd/udp + scripts/udp_interop.py`：新增仅绑定本地回环的有界 UDP 设备宿主，配置端口和最多报文数，维护 peer 映射并周期驱动 COV。独立 BACpypes3 经实际 UDP 验证发现、优先级读写/释放、错误回复、坏报文恢复和订阅通知/取消。

复杂度与代价：宿主最长15秒、对端上限128、每100ms轮询；时钟使用宿主秒数并夹持为非递减。它是本地集成/模拟宿主，尚非长运行现场网关。

## 运行

```sh
moon run examples/november --target native --deny-warn
moon check --target all --deny-warn
moon build --target all --deny-warn
moon test --target all --deny-warn
```

Windows当前工具链路径问题沿用README的项目适配脚本；正式命名空间为 `erzhuzi259/moonbacnet`，安装方式见README。

## 范围

不包含 MS/TP、BBMD、路由、BACnet/SC、分段 APDU、全部标准对象必备属性或 BTL 认证。设备目录和 priority 不是认证授权系统；UDP宿主只面向回环集成，外部设备与跨网部署仍需后续开发及验证。

52项原测试基础上新增发现冲突/过期与优先级诊断测试；原stdio对照和新真实回环UDP对照均单独执行。 具体当前执行结果由本地检查记录提供，不以CI配置代替远端成功记录。

## 回环UDP联调

```sh
moon build --target native --deny-warn
python scripts/udp_interop.py
moon run cmd/udp --target native -- 0 12
```

独立脚本使用现有requirements-interop.txt中的BACpypes3，先按README安装到_local/oracle。脚本自动选择回环临时端口，最多处理12个报文并在20秒内终止测试。手动宿主最长运行15秒，收到指定报文数后正常关闭，超时以失败退出；不是常驻设备服务。端口0仅用于临时本地联调。UDP丢包/防火墙/厂商设备仍需宿主集成验证。
