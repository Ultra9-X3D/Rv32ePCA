# 寄存器与 Frame 引脚

[文档导航](README.md) · [架构与操作码](architecture.md)

定义依据：[APB RTL](../rtl/Apb4Rv32ePca.v)、[Frame 顶层](../rtl/Rv32ePca.v)。

## APB4 寄存器

寄存器位于 256-byte aperture 内，要求 32 位对齐。`PREADY` 恒为 1；未实现地址、
未对齐访问以及向只读寄存器写入会在 access phase 置 `PSLVERR`。`PPROT` 被接受但
不参与权限判断。

| Offset | 名称 | 属性 | 说明 |
| ---: | --- | --- | --- |
| `0x00` | ID | RO | `0x50434134`，ASCII `PCA4` |
| `0x04` | CAPS | RO | `0x010A0804`：v1、10 ops、8-bit、4 lanes |
| `0x08` | CTRL | RW/W1P | `[3:0] opcode`、`[4] IRQ_EN`、`[8] START` |
| `0x0C` | STATUS | RO | `[0] BUSY`、`[1] DONE`、`[2] IRQ`、`[3] ERROR`、`[15:8] cycles` |
| `0x10` | OPERAND_A | RW | packed four lanes，支持 `PSTRB` |
| `0x14` | OPERAND_B | RW | packed four lanes，支持 `PSTRB` |
| `0x18` | ACC | RW | DOT/SAD 初值，支持 `PSTRB` |
| `0x1C` | RESULT | RO | 最近一次结果 |
| `0x20` | PERF | RO | `[7:0]` 最近一次计算周期数 |
| `0x24` | IRQ_CLEAR | WO | bit 0 清 DONE，bit 1 清 ERROR |

`START` 是写一脉冲，不会保存在 CTRL。busy 期间重复 START 不重启计算，而是置
`STATUS.ERROR`；软件在提交新命令前应先检查 BUSY。`IRQ = IRQ_EN & DONE`。

## Frame 引脚

| 用户设计 `io[]` | 方向 | 信号 |
| --- | --- | --- |
| `[31:0]` | 双向 | APB DATA；写时外部控制端驱动，读时加速器驱动 |
| `[37:32]` | 输入 | word address，即 `PADDR[7:2]` |
| `[41:38]` | 输入 | `PSTRB[3:0]` |
| `[42]` | 输入 | `PSEL` |
| `[43]` | 输入 | `PENABLE` |
| `[44]` | 输入 | `PWRITE` |
| `[45]` | 输出 | `PREADY` |
| `[46]` | 输出 | `PSLVERR` |
| `[47]` | 输出 | completion IRQ |
| `[65:48]` | 高阻 | 保留 |

外部芯片引脚关系为：

```text
FrameTop.user_io[n + 7] <-> Rv32ePca.io[n]
```

读事务时外部 master 必须释放 DATA；设计在 `PSEL=1 && PWRITE=0` 的 setup 与
access phase 驱动 DATA。写事务时设计释放 DATA，由 master 驱动。`PREADY`、
`PSLVERR` 和 IRQ 三位始终由设计驱动。


## 一次 DOT4 调用

所有地址都是相对基地址的字节偏移。以 A=`0x04030201`、B=`0x08070605` 为例：

1. 读 `STATUS(0x0C)`，确认 BUSY=0。
2. 写 `OPERAND_A(0x10)=0x04030201`，写 `OPERAND_B(0x14)=0x08070605`。
3. 写 `CTRL(0x08)=0x00000104`：START=1，opcode=4，IRQ_EN=0。
4. 轮询 STATUS 的 DONE 位，随后读 `RESULT(0x1C)`，期望 70。
5. 写 `IRQ_CLEAR(0x24)=1` 清 DONE。

普通全字写使用 `PSTRB=0xF`。在 Frame 引脚上，CTRL 的 word address 是 `0x08 / 4 = 2`，不是字节偏移 8。

## 已知接口边界

- `PADDR[31:8]` 不参与内部解码，当前 Frame 顶层只提供低位寄存器偏移，并将高位地址固定为零。
- 当前 RTL 对未对齐访问会置 PSLVERR，但写使能没有用地址对齐条件门控，未对齐写仍可能修改寄存器或触发 START。软件必须对齐访问；若要保证错误事务无副作用，需要单独修复 RTL。Frame 顶层会将地址低两位固定为零。
- `STATUS.ERROR` 记录忙时重复 START，不代表所有 APB 错误；PSLVERR 与该状态位不同。
- 保留操作码当前返回 0，不会自动设置 ERROR；调用方不应使用这些操作码。
- IRQ 是 `IRQ_EN && DONE` 电平信号，清 DONE 后撤销。成功接受新命令会清旧 DONE 和 ERROR。
- ACC 不会被结果自动更新；连续累加由软件把 RESULT 写回 ACC。
