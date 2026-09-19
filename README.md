# Zynq-7020 双霍尔门小车测速仪

基于 **XC7Z020-2CLG484I** 的双霍尔门小车测速系统。项目完全运行在
Zynq-7000 的 PL 侧，使用两只固定霍尔传感器测量小车经过两道门的时间，
判断运动方向并计算速度。

> 当前默认门距 `500 mm`、速度范围 `50–5000 mm/s` 是工程参数，不代表
> 实物已经完成最终标定。实际使用前必须测量双向有效触发距离并修改参数。

## 功能

- 双霍尔门顺序判断：`A → B` 为正向，`B → A` 为反向；
- 50 MHz 时钟计时与 64 位无符号除法；
- 霍尔异步输入同步及连续稳定时间滤波；
- 板载 USB-UART 输出，例如 `F,2500` 或 `R,2500`；
- TM1637 四位数码管显示速度；
- LED1 测速成功闪烁，LED2 指示方向；
- 双路XADC以约50 k组/秒采样，并分别保存霍尔A、霍尔B触发窗口；
- ILA可现场观察AO码值、采样有效信号和数字霍尔事件；
- 两个触发窗口自动通过UART导出，电脑脚本生成CSV和波形图；
- 自检仿真覆盖正向、反向、UART和TM1637活动。

TM1637驱动会在ACK周期释放DIO，但当前版本不采样ACK；因此显示器断线不会作为
运行时错误上报。

## 目标硬件

- 开发板：鹿小班 LXB-ZYNQ7000；
- FPGA：`XC7Z020-2CLG484I`；
- Vivado Part：`xc7z020clg484-2`；
- Vivado：2022.2；
- 两只带数字输出和AO输出的霍尔传感器模块；
- 一块 3.3 V / 5 V 双向 NMOS 电平转换板；
- 5 V TM1637 四位数码管；
- 一块固定在小车上的磁铁。

详细接线见 [docs/hardware-wiring.md](docs/hardware-wiring.md)，开发板引脚见
[docs/pinout.md](docs/pinout.md)。

## 仓库结构

```text
rtl/          SystemVerilog可综合RTL
constraints/  Vivado XDC约束
sim/          XSim测试平台
scripts/      工程重建、仿真与生成bitstream脚本
docs/         接线、引脚、标定和故障排查
```

不提交 Vivado 的缓存、运行目录、检查点和 bitstream。项目通过 Tcl 脚本从
源码重建，避免 `.xpr` 中的绝对路径和工具生成状态污染仓库。

## 快速开始

Windows PowerShell 中进入仓库根目录。包装脚本会把Tcl文件转换成绝对路径，
避免Vivado启动器错误解析相对路径。

创建工程：

```powershell
& 'D:\vivado\Vivado\2022.2\bin\vivado.bat' -mode batch `
  -source (Resolve-Path '.\scripts\create_project.tcl')
```

双霍尔数字边沿与双AO采样共用的工程名为 `car2`。创建后工程文件位于：

```text
build/car2/car2.xpr
```

AO波形缓存、ILA和电脑端绘图的使用说明见
[docs/ao-waveform-capture.md](docs/ao-waveform-capture.md)。

重建 `car2` 工程：

```powershell
& 'D:\vivado\Vivado\2022.2\bin\vivado.bat' -mode batch `
  -source (Resolve-Path '.\scripts\create_ao_project.tcl')
```

运行仿真：

```powershell
.\scripts\run_sim.ps1
```

仿真日志应包含：

```text
PASS forward: speed=5000 mm/s
PASS reverse: speed=5000 mm/s
ALL TESTS PASSED
```

生成 bitstream：

```powershell
.\scripts\build_bitstream.ps1
```

如果Vivado不在默认位置，显式传入安装路径：

```powershell
.\scripts\run_sim.ps1 -VivadoBat 'C:\Xilinx\Vivado\2022.2\bin\vivado.bat'
```

输出默认位于：

```text
build/vivado/hall_gate_speed.runs/impl_1/hall_gate_speed_top.bit
```

## 已验证状态

以下结果由 Vivado 2022.2、器件 `xc7z020clg484-2` 实际运行得到：

- XSim：正向、反向测试均通过，最终输出 `ALL TESTS PASSED`；
- 综合：0 errors、0 critical warnings；
- 实现：布局布线完成，未布通网络为0；
- 时序：WNS `6.256 ns`、WHS `0.130 ns`，全部用户时序约束满足；
- 方法学检查：0 violations；
- 资源：970 LUT、719寄存器；
- bitstream：成功生成。

DRC仅保留纯PL Zynq工程预期的`ZPS7-1`警告，含义与使用边界见下一节。

## JTAG临时烧录

1. 断电连接14针JTAG排线，BOOT1/BOOT2设为 `ON/ON`；
2. 分别连接开发板供电USB-C和SMT2-HS下载器USB；
3. Hardware Manager → Open Target → Auto Connect；
4. 选中 `xc7z020` → Program Device → 选择生成的 `.bit`；
5. JTAG配置掉电后丢失，重新上电需要再次烧录。

纯PL设计生成bitstream时，Vivado会给出`ZPS7-1: PS7 block required`警告。
本项目不包含未经验证的PS7板级预设，因此只支持已验证的JTAG临时配置流程；
制作QSPI/SD永久启动镜像前，必须补充适用于该板的PS7配置和FSBL。

板载 USB-C 串口与 JTAG 下载器是两个独立接口。串口使用 `115200, 8N1`，
关闭硬件流控和十六进制显示。

## 参数修改

主要参数位于 `rtl/hall_gate_speed_top.sv`：

- `DIST_FWD_MM`：A到B方向的有效距离；
- `DIST_REV_MM`：B到A方向的有效距离；
- `FILTER_US`：霍尔数字输入稳定滤波时间；
- `MIN_SPEED_MM_S`、`MAX_SPEED_MM_S`：接受的速度范围；
- `HALL_ACTIVE_LOW`：霍尔数字输出有效极性。

有效距离不是亚克力架的标称间距，而是同一磁铁、同一安装高度和方向下，
两只传感器实际触发位置之间的距离。标定步骤见
[docs/calibration.md](docs/calibration.md)。

## 安全说明

- Zynq PL数字I/O只允许3.3 V，禁止5 V直接进入 `G15/G16/C19/D18`；
- 电平转换板必须同时连接 `VCCA=3V3` 与 `VCCB=+5V`，并且共地；
- FPGA接低压A侧，5 V传感器和TM1637接高压B侧；
- `AO`不得接入普通数字GPIO或NMOS电平转换板；启用双AO扩展时，只能经已验证的分压/RC网络接入XADC模拟输入；
- 每次修改接线前断电；板灯变暗、USB掉线或器件发热时立即断电。

## 许可证

本项目代码使用 [MIT License](LICENSE)。仓库不包含开发板厂商资料、Vivado、
驱动程序或其他第三方二进制文件。
