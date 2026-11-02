# 基于FPGA校园多场景智显终端——评委检查完整代码

本包整理完成日期：2026-11-02。采用已完成实板烧录与功能确认的 **10-26 TF冷启动恢复版**，仅整理提交结构、补充复现说明，不修改RTL、字库数据、引脚或时序约束。

## 1. 唯一版本身份
- FPGA：EG4S20BG256；开发板：HX4S20C。
- 开发环境：安路Tang Dynasty 6.2；顶层：`audio_final/integrated/top_final.v`，模块`top`。
- 版本提交：`68880be6044b140cbe4e59483f408af77db256b4`。
- 已验证位流：`artifacts/BOARD_TEST_10_26_TF_COLDBOOT_RECOVERY_seed59.bit`。
- 位流SHA-256：`6E948478CAED10522D6205F88F89726103610028ADDE6D09A0B617816E41528C`。
- 最终实现：LUT 17786、REG 8943、Slice 9641、BRAM9K 52、BRAM32K 13、DSP 14；Setup WNS +0.118 ns、Hold WNS +0.020 ns。

## 2. 目录
|目录/文件|内容|
|---|---|
|pic_sdram_audio_final.al|最终TD工程，完整保留源文件登记、编译顺序、器件与约束|
|src/|图像装载、场景控制、OSD、消抖、跨域、帧资格、SDRAM等逻辑及字库数据|
|al_ip/|PLL、FIFO生成文件和相关参数|
|audio_final/integrated/|最终集成顶层|
|audio_final/rtl/、audio_board/rtl/、audio_board/vendor/|音频、可视化、HDMI封装与配套IP|
|top.adc、audio_board/integrated/audio.sdc|最终引脚及时序约束|
|sim/tb/、tb/、audio_final/tb/、sim/evidence/|仿真源与器件行为模型，不能加入综合文件集|
|tools/|串口上位机、TF素材工具、素材/字库生成脚本和回归脚本|
|artifacts/|唯一已验证烧录位流|
|verification/|最终物理实现报告、原发布验证日志及提交整理检查记录|
|docs/|操作与串口协议说明|
|media_examples/|现有演示素材（如有），与源码分开|
|PACKAGE_MANIFEST.json、SHA256SUMS.txt|文件来源、版本对应关系与完整性校验|

## 3. 打开与构建
1. 将整个`FPGA_Campus_Final`解压到英文、无空格的短路径，例如`E:/FPGA_Campus_Final`，不要单独移动顶层或字库文件。
2. 双击`准备工程路径.bat`生成本机便携构建副本，再用TD 6.2打开`build/portable_project/pic_sdram_audio_final.al`。副本仅调整工程根路径与5个字库INIT_FILE路径，字库内容和功能逻辑不变；包内原始RTL保持逐字节一致。
3. 保持顶层`top`、器件EG4S20BG256、原编译顺序与约束。部分模块由`include`引入，不能再次手工加入综合文件集。
4. 如需完整重建，在终端切至本包根目录，执行`td tools/build_final_seed59.tcl`（或使用TD安装目录中的td_commands_prompt.exe执行该脚本）。脚本使用seed 59，输出`build/final_seed59/REBUILT_final_seed59.bit`，不会覆盖已验证位流。
5. 器件原语、加密HDMI/SDRAM IP由TD环境支持；包内已附工程使用的封装和加密源。仿真行为模型只供仿真使用。
6. 应急大字库以相对路径加载，必须保留`src/emergency_big_font_bank0.dat`至`bank4.dat`。准备脚本在生成副本中将5个INIT_FILE替换为本机完整路径，避免TD展开include后对相对路径解释不同；原始字库数据不作重新生成。

## 4. 仿真复查
安装Icarus Verilog并将`iverilog`、`vvp`加入PATH后，在项目根目录执行：
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_iverilog_full_regression.ps1
```
脚本包含56项维护用例；输出在`sim/_evidence_full_iverilog`。部分用例为独立算法/接口模型，不等同于完整顶层物理实现仿真。原56项日志及12组ModelSim代表复核日志已附于`verification/`；本次提交整理检查另存独立目录。在ModelSim中执行`do tools/run_modelsim_representative.do`可运行12组代表用例。

## 5. 上位机与素材
在Python 3环境执行`pip install -r tools/requirements.txt`，运行`tools/welcome_uart_gui.py`或双击`tools/启动迎新串口上位机.bat`。
上位机用于迎新/应急滚动通知配置，以及离线图片、音频素材制作。图片使用FAT32根目录大写8.3文件名；当前抢答3题，QUIZ1～3为题目、QUIZ4～7为队伍页面，QUIZ8是历史素材槽位名称而非8道题。
迎新音乐经工具转换为48kHz、16bit、单声道裸PCM，写入TF卡LBA 300000起的38464个扇区；并非FPGA直接解析任意WAV文件。写卡须核对目标盘，图片更新后最后写入音乐并校验。
`docs/原版使用手册_操作映射参考.md`保留原操作表；其中旧版本名称、位流推荐和历史资源数据以本README为准。

## 6. 烧录
BitWriter列表只保留`artifacts/`中本包唯一位流。固化选择`PROGRAM_FLASH / 5 MHz / 128 Mbits`；完成后完全断电再上电确认。`PROGRAM_SRAM`仅临时下载，断电不保留。

## 7. 本包边界
保留可复核所需的完整代码、IP/字库依赖、测试源、约束、上位机与发布证据；排除历史位流、失败候选、EDA数据库、工具安装包、巨量波形和临时缓存。源码注释中的旧日期、旧模块名保留原貌，不作为本包版本身份。重建位流必须重新检查实现结果；本包推荐烧录的仍是上述原已验证位流。
