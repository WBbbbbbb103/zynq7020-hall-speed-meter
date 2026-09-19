# car2 双路AO波形观察与导出

## 1. 已实现的数据路径

`car2` 同时保留数字测速和双路AO采集：

```text
霍尔A数字输出 → G15 → 滤波/边沿 → A事件触发
霍尔B数字输出 → G16 → 滤波/边沿 → B事件触发

霍尔A AO → 10k/2k分压与RC → VAUX0 → adc_a
霍尔B AO → 10k/2k分压与RC → VAUX8 → adc_b

adc_a + adc_b → A事件环形BRAM
              → B事件环形BRAM
              → ILA实时探针
              → UART自动导出 → CSV/PNG
```

## 2. 采样窗口

- 名义双通道采样率：约 `50 k组/秒`；
- A事件缓存：`16384`组双通道样本；
- B事件缓存：`16384`组双通道样本；
- 每个窗口触发前：`4096`组，约 `81.92 ms`；
- 每个窗口从触发到结束：`12288`组，约 `245.76 ms`；
- 每个完整窗口：约 `327.68 ms`。

A、B使用独立BRAM，即使两个数字触发的间隔小于一个采样窗口，也不会互相覆盖。
上电或按下KEY1后重新开始一次采集；A、B两个窗口都完成后，UART自动导出。

## 3. ILA探针

| Probe | 宽度 | 含义 |
|---|---:|---|
| `probe0` | 12 | `adc_a`，VAUX0原始码 |
| `probe1` | 12 | `adc_b`，VAUX8原始码 |
| `probe2` | 1 | `sample_valid`，新样本有效 |
| `probe3` | 1 | `hall_a_active` |
| `probe4` | 1 | `hall_b_active` |
| `probe5` | 1 | `hall_a_event`，A触发脉冲 |
| `probe6` | 1 | `hall_b_event`，B触发脉冲 |
| `probe7` | 1 | A窗口采集完成 |
| `probe8` | 1 | B窗口采集完成 |

ILA采样时钟为50 MHz。观察AO波形时，在ILA的Capture Control中使用
`probe2 == 1`作为存储条件，使缓存只保存新的ADC样本；触发条件选择
`probe5 == 1`或`probe6 == 1`。

## 4. UART导出格式

串口参数：`115200, 8N1`，无硬件流控。板载CH340从 `L17` 接收FPGA数据。

导出格式：

```text
#CAR2AO
A,0000,ABC,DEF
...
A,3FFF,ABC,DEF
B,0000,ABC,DEF
...
B,3FFF,ABC,DEF
#END
```

每行依次为事件名、样本序号、AO-A的12位十六进制码、AO-B的12位十六进制码。
完整导出约需45秒。传输期间不要按KEY1、断电或关闭串口。

## 5. 电脑端自动保存和绘图

先安装：

```powershell
python -m pip install pyserial matplotlib
```

查看设备管理器确定开发板USB串口号，例如 `COM5`，然后在项目根目录运行：

```powershell
python .\tools\plot_car2_ao.py --port COM5 --output .\capture\run01
```

脚本等待 `#CAR2AO`，接收完后生成：

```text
capture/run01.txt   原始UART数据
capture/run01.csv   时间、ADC码和电压数据
capture/run01.png   A/B两个事件窗口的双路AO图
```

默认按10 kΩ/2 kΩ分压，即原AO电压约为XADC端电压的6倍。若实测电阻得到不同
分压比，可使用：

```powershell
python .\tools\plot_car2_ao.py --port COM5 --divider-ratio 6.012 \
  --output .\capture\run01
```

也可以重新处理以前保存的原始文件：

```powershell
python .\tools\plot_car2_ao.py --input .\capture\run01.txt \
  --output .\capture\run01_replot
```

## 6. 仍需实物确认的量

- 50 k组/秒是当前配置的名义值，最终应通过ILA测量相邻`sample_valid`间隔确认；
- XADC码与原AO电压的斜率和零偏需要用万用表/精密电压源标定；
- 任一VAUX输入都不得超过1.0 V；
- 波形出现长时间`000`或`FFF`意味着断线、接反或饱和，不能直接进入速度拟合。
