# First run tools/prepare_project.ps1. Build copy changes only host-dependent font paths.
set base [file normalize [file dirname [file dirname [info script]]]]
set root $base/build/portable_project
set out $base/build/final_seed59
file mkdir $out
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
bitgen -bit $out/REBUILT_final_seed59.bit
puts "REBUILD_FINAL_DONE"
exit
