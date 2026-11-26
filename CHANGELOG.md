# Changelog

## Unreleased — 2026-11-26

- 补充 Device 与普通 IPv4 Network Port 身份、能力和属性构建。
- 实现 Who-Has／I-Have、设备通配寻址、RPM 必需和可选属性选择器。
- 补充脱机输入写入、对象改名、当前命令优先级和默认值写入。
- 实现确认型 COV 的通知、接收去重、ACK、有界重传与取消。
- 对分段确认请求返回标准 Abort，增加标准交互示例和独立协议验证。

## 0.2.0 — 2026-11-25

- 按 I-Am 公告的 APDU 上限和本地预算拆分 ReadPropertyMultiple，保留对象、属性和数组索引的顺序。
- 增加 `ReadBatch`、`compile_read_batches` 和 `correlate_read_batches`，对照原始请求核验响应，并保留设备返回的属性级错误。
- `DiscoveryDirectory::lookup` 按设备标识查找仍有效的记录，`discovery_delta` 报告设备迁移、能力变化及增删。
- `Client::next_deadline` 提供请求的下一次重试或失效时刻，供宿主调度。
- `Device::apply_commands` 在设备本地原子提交多个设定点的优先级写入，任一请求失败时回滚。
- 扩展示例贯通发现、按 APDU 拆分、驱动客户端期限和对回 19 个属性结果，包含数组索引和未知对象错误。

## 0.1.0 — 2026-11-02

- 设备发现与冲突目录：DiscoveryDirectory
- 命令仲裁可解释快照：Device::command_snapshot
- Native UDP 接入与独立网络验证：cmd/udp + scripts/udp_interop.py
- 增加边界回归、可运行集成示例和CI步骤。

### Initial implementation

- Typed application/context tags, strict bounded BVLC/NPDU/unsegmented APDU codecs.
- Who-Is/I-Am, property reads/writes, RPM choices and unconfirmed COV service formats.
- Object registry, computed arrays, typed point domains and command priority/relinquish semantics.
- COV lifetimes and cumulative thresholds; peer request correlation, retry/timeout and bounded replay cache.
- HVAC, energy inventory, equipment monitoring and sustained bounded workload examples.
- Four-backend tests, independent BACpypes3 wire/device-host checks, CI and package hygiene.

Public namespace: erzhuzi259/moonbacnet; fixed compiler/core, Linux/Windows CI and history/package hygiene checks.
