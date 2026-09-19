# 开发板引脚说明

以下名称全部采用开发板实物丝印和FPGA球位，不使用容易混淆的“GPIO编号”。

| 功能 | 顶层端口 | 板载丝印/球位 | 电平 | 说明 |
|---|---|---:|---|---|
| PL时钟 | `clk_50m` | `M19` | 3.3 V | 板载50 MHz |
| 霍尔门A | `hall_a_in` | `G15` | 3.3 V | 异步输入、RTL同步滤波 |
| 霍尔门B | `hall_b_in` | `G16` | 3.3 V | 异步输入、RTL同步滤波；F16保留给VAUX0P |
| TM1637 CLK | `tm_clk` | `C19` | 3.3 V | 必须经过电平转换 |
| TM1637 DIO | `tm_dio` | `D18` | 3.3 V | 开漏/高阻，必须经过电平转换 |
| 板载UART发送 | `uart_tx` | `L17` | 3.3 V | 连接板载CH340 RX |
| KEY1复位 | `pl_key1_n` | `K21` | 低有效 | 板载按键，按下为低 |
| LED1 | `pl_led1` | `P20` | 高亮 | 测速成功闪烁约100 ms |
| LED2 | `pl_led2` | `P21` | 高亮 | 亮=A到B，灭=B到A |

扩展排针电源使用板载丝印 `3V3`、`+5V` 和 `GND`。禁止根据排针位置猜测，
接线前同时核对丝印和线色。

双AO扩展使用 `F16/E16=VAUX0P/N` 和 `D16/D17=VAUX8P/N`。Vivado约束中
将这四个端口标记为 `LVCMOS33`，仅用于满足Bank 35的VCCO兼容性检查；引脚
实际仍连接XADC模拟通道，输入范围仍为0–1.0 V。AO不得经过NMOS电平转换模块，
完整接法见 `docs/dual-ao-instantaneous-speed-plan.md`。

约束文件：`constraints/hall_gate_speed.xdc`。
