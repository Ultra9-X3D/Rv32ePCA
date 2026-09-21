# Rv32ePCA

MPC Frame 四路 INT8 并行计算加速器，保存最终选定的 **ECOS Studio `ws_0002` 组合乘法版本**。顶层为 `Rv32ePca`，设计自身不含 CPU。

四路 8×8 有符号乘法并行执行，支持点积、点积累加、逐字节加减、无符号绝对差及其求和累加、位运算和复制，共 10 类操作。接受 START 后一个计算周期提交结果，操作数传输及寄存器访问时间另计。接口采用 Frame 66 位用户载荷上的 APB 风格协议。

## 文件入口

| 目录或文件 | 内容 |
|---|---|
| [设计报告](docs/design-report-ws_0002.md) | 面向审核的功能、指标、面积、利用率与回片测试计划 |
| [审核记录](docs/review-ws_0002.md) | 验证结果、模型修正前提及尚未闭合的验证 |
| [架构](docs/architecture.md)、[寄存器与引脚](docs/registers-and-pins.md) | 运算、时序、调用方式 |
| `rtl/` | `ws_0002/origin` 的三份原始 RTL，逐字节保留 |
| `design.json` | MPC Frame 用户设计清单 |
| `tests/` | RTL 单元、Frame 集成及后端网表功能测试平台 |
| `constraints/pca.sdc` | ws_0002 原始 50 MHz 时钟约束 |
| `reports/` | 综合、后端及功能验证记录 |
| [submission/pca_sta.def](submission/pca_sta.def)、[submission/pca_sta.v](submission/pca_sta.v) | 同一工作区 STA 阶段导出的布局文件和标准单元网表 |
| `SHA256SUMS.json` | RTL、约束、提交文件的 SHA-256 校验值 |

## ws_0002 指标

| 指标 | 结果 |
|---|---:|
| 目标时钟 | 50 MHz |
| 综合映射标准单元 | 4082 个，9462.04 μm² |
| 后端逻辑单元 | 4100 个，9525.88 μm² |
| 用户模块 Die 面积 | 33014.88 μm² |
| Core 利用率 | 30.1641% |
| 总实例 | 13533 个，含 9433 个物理单元 |

5000 个单元目标针对综合映射逻辑规模。144 MHz 是后端工具估算频率，不能作为回片工作频率承诺。

## 运行测试

在 Linux/WSL 中安装 Python 3、Verilator 和 C++ 编译工具链后，从仓库根目录执行：

```bash
python3 scripts/check_hashes.py
python3 scripts/run_tests.py
```

`run_tests.py` 默认运行原始 RTL 单元测试，生成 `build/rtl_run.log`。历史审核环境为 Verilator 5.046；使用其他版本时应重新验证。

网表功能回归需自行准备 ics55 标准单元库，`--cell-root` 指向含 `ics55_LLSC_H7CR`、`ics55_LLSC_H7CL` 子目录的目录：

```bash
python3 scripts/run_tests.py --gate --cell-root /path/to/ics55_LLSC_H7C_V1p10C100
```

PDK、完整模型库和 CPU 工程不随本仓库分发。

Frame 集成测试需外部 MPC Frame 工程。将本仓库内容放入其 `designs/rv32e-pca-5000inst/` 后，在框架根目录运行：

```bash
make user-check DESIGN=designs/rv32e-pca-5000inst
```

Framework 负责生成 `UserDesignDut`、注册表及分配测试编号。最终芯片的编号和启动时序以组织方集成版本为准。

## 版本与验证范围

已有 RTL/Frame 功能测试、5120 用例的处理器联合仿真，以及注明模型修正前提的零延时提交网表回归证据。处理器联合仿真日志归档于 `reports/verification/`，完整 CPU/桥接环境未随仓库发布。

尚未完成 RTL/网表形式等价、带 SDF 延时验证和硅上测试。原始 SDC 未定义外部输入输出延时，最终 Frame 接口时序仍需复核。ECOS DRC/iLVS 检查不代替组织方最终工艺签核。
