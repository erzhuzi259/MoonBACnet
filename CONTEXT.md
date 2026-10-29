# BACnet 对象属性

建筑设备通过标识明确的对象和类型化属性交换状态与控制意图。

## Language

**Object Identifier**：对象类型与实例号组成的 BACnet 标识，不是设备地址。

**Property Reference**：对象属性及可选数组索引；索引0代表数组长度，缺省索引代表整个属性。

**Command Priority**：命令占用的1至16级优先级槽，数值较小的已占槽生效；释放槽不等于写入零。

**Relinquish Default**：所有命令优先级槽均已释放时的默认值。

**COV Subscription**：订阅者对某对象状态变化的有限期关注；不是持久消息队列。

**Invoke ID**：单个对端地址范围内关联请求与响应的事务编号，不是全局消息标识。
