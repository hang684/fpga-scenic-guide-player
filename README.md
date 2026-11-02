# 九寨沟景区车载多媒体展示终端

基于安路 EG4S20BG256 FPGA 与 HX4S20C 开发板的车载导览播放系统，通过 HDMI 输出 640×480 画面与 48 kHz 音频，实现景点图片、讲解音频与字幕的联动播放。

## 主要功能

- 从 FAT32 TF 卡读取 BMP 图片与裸 PCM 音频，四 bank SDRAM 帧缓存 + 帧边界提交实现无撕裂转场
- 800×600、1024×768 素材经最近邻坐标映射实时适配 640×480 有效区
- HDMI 音频（48 kHz，复用 25 MHz 像素时钟）与 I²S 麦克风现场录音，A/B 双槽 CRC 校验后写入
- OSD 菜单、缩略图选景、亮度对比度调节、滚动字幕、音频波形与频谱可视化
- 配置断电保存，上电自检恢复上次景点与参数

## 目录结构

- `src/user_source/hdl_source`  RTL 源码（视频链路、FAT32、录音、UI）
- `src/user_source/constraints_source`  时序与引脚约束
- `src/td_project`  Tang Dynasty 工程与综合实现结果
- `tests`  testbench
- `tools`  素材准备与录音格式工具

## 硬件平台

安路 EG4S20BG256（TD 6.2），逻辑金信 HX4S20C 开发板，TF 卡、HDMI 显示、INMP441 麦克风。
