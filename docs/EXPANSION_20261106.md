# MoonBACnet 增量功能：2026-11-06

本页功能自 0.2.0 起随发行版提供。

## 本地多点命令原子提交与设备目录语义差异
`Device::apply_commands(requests)` 对本地 commandable 对象的 Present_Value(85) 批量写入进行暂存。
全部请求通过优先级、值域、对象、属性和单值校验后才一次提交；任意后续请求失败都不改变原状态。
重复对象共用暂存优先级数组，返回每个受影响对象的最终 CommandSnapshot（首次出现顺序）。
支持以 Null 释放指定优先级、恢复下层策略。请求数受 Device 的 max_pending 限制。
这是单进程、单调用的本地原子操作，不是网络 WritePropertyMultiple、数据库事务或并发控制。

`discovery_delta(before, after, maximum~=256)` 按设备实例号匹配快照，输出 added/removed/changed。
端点、厂商、max APDU 或分段能力改变才算 changed；单纯 last_seen 刷新不产生拓扑噪声。
校验 I-Am 字段、重复实例、时间顺序、peer 长度和每侧数量（maximum 1..65536）。
结果数组独立，排序遵循对应输入首次顺序。

楼宇自动化和设备互联是主要场景：房间与设备设定点联动、运维覆盖优先级撤销、
网关设备迁移审计；亦可服务园区能耗采集、实验设备目录及离线 BACnet 数据分析。
不宣称与所有厂商设备认证兼容，不替代现场授权、调度或安全联锁。

R 个请求、D 个本地对象、A 个受影响对象，暂存命令时间 O(R(D+A))、空间 O(16A)。
目录差异期望 O(N+M) 时间、O(N+M) 空间（另含端点文本校验）。
测试覆盖末项失败回滚、重复对象、优先级释放、旧快照隔离、刷新忽略、迁移/增删及重复实例拒绝。

## 运行

```sh
moon run examples/expansion --target native --deny-warn
moon test --target all --deny-warn
```

Windows 使用 README 中对应的 Moon 包装脚本替代 `moon`。
扩展示例还执行 I-Am 目录查找、按 APDU 上限拆分请求、读取客户端期限和关联 19 个属性结果。CI 运行该示例，无需外部网络服务或真实设备。
