# TF 卡冷启动协议空闲电平 + 首次挂载自动恢复版。
# 独立构建目录和位流，不覆盖任何已验证发布文件。
set root E:/FPGA/ALST/_dev_sim_0b18789
set out  $root/_build_tf_coldboot_recovery_seed59
set art  $root/artifacts

file mkdir $out
file mkdir $art
cd $root

import_device eagle_s20.db -package EG4S20BG256
open_project $root/pic_sdram_audio_final.al -single_run
load_run_param -run syn_1

cd $out
elaborate -top top
read_adc $root/top.adc
read_sdc $root/audio_board/integrated/audio.sdc
optimize_rtl
optimize_gate $out/gate.area
legalize_phy_inst
update_timing

load_run_param -run phy_1
set_param place seed 59
place
route
fix_hold
update_timing -mode final

report_qor -step route -file $out/route.qor
report_area -io_info -file $out/final.area
report_timing_summary -file $out/final.timing
bitgen -bit $art/BOARD_TEST_10_26_TF_COLDBOOT_RECOVERY_seed59.bit

puts "BUILD_TF_COLDBOOT_RECOVERY_SEED59_DONE"
exit
