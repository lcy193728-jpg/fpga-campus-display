# Run from ModelSim: do tools/run_modelsim_representative.do
set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root sim modelsim_representative]
file mkdir $out
onerror {quit -code 1 -f}
onbreak {resume}
set idx 0
cd $root
catch {quit -sim}
set lib [file join $out 01_coldboot_spi_quiz_work work]
file mkdir [file dirname $lib]
if {![file exists $lib]} {vlib $lib}
vmap work $lib
cd $root
set files [list [file join $root {src/sd_powerup_guard.v}] [file join $root {src/sd_card/spi_master.v}] [file join $root {src/sim_modules/quiz_arbiter_4ch.v}] [file join $root {sim/evidence/tb_evidence_core_timing.v}]]
eval vlog -work work [list +incdir+$root/src +incdir+$root/audio_final/tb] $files
cd $root
vsim -onfinish stop -t 1ps work.tb_evidence_core_timing
run -all
puts "MODELSIM_CASE_COMPLETED 01_coldboot_spi_quiz"
catch {quit -sim}
set lib [file join $out 02_first_frame_gate_work work]
file mkdir [file dirname $lib]
if {![file exists $lib]} {vlib $lib}
vmap work $lib
cd $root
set files [list [file join $root {src/video_first_frame_gate.v}] [file join $root {sim/tb/tb_video_first_frame_gate.v}]]
eval vlog -work work [list +incdir+$root/src +incdir+$root/audio_final/tb] $files
vsim -onfinish stop -t 1ps work.tb_video_first_frame_gate
run -all
puts "MODELSIM_CASE_COMPLETED 02_first_frame_gate"
catch {quit -sim}
set lib [file join $out 03_scene_load_guard_work work]
file mkdir [file dirname $lib]
if {![file exists $lib]} {vlib $lib}
vmap work $lib
cd $root
set files [list [file join $root {src/scene_load_guard.v}] [file join $root {sim/tb/tb_scene_load_guard.v}]]
eval vlog -work work [list +incdir+$root/src +incdir+$root/audio_final/tb] $files
vsim -onfinish stop -t 1ps work.tb_scene_load_guard
run -all
puts "MODELSIM_CASE_COMPLETED 03_scene_load_guard"
catch {quit -sim}
set lib [file join $out 04_quiz_key_arbiter_work work]
file mkdir [file dirname $lib]
if {![file exists $lib]} {vlib $lib}
vmap work $lib
cd $root
set files [list [file join $root {src/sim_modules/key_sync_debounce.v}] [file join $root {src/sim_modules/key_edge_detect.v}] [file join $root {src/sim_modules/quiz_arbiter_4ch.v}] [file join $root {sim/tb/tb_quiz_key_chain.v}]]
eval vlog -work work [list +incdir+$root/src +incdir+$root/audio_final/tb] $files
vsim -onfinish stop -t 1ps work.tb_quiz_key_chain
run -all
puts "MODELSIM_CASE_COMPLETED 04_quiz_key_arbiter"
catch {quit -sim}
set lib [file join $out 05_quiz_end_commit_work work]
file mkdir [file dirname $lib]
if {![file exists $lib]} {vlib $lib}
vmap work $lib
cd $root
set files [list [file join $root {src/quiz_end_commit_guard.v}] [file join $root {sim/tb/tb_quiz_end_commit_guard.v}]]
eval vlog -work work [list +incdir+$root/src +incdir+$root/audio_final/tb] $files
vsim -onfinish stop -t 1ps work.tb_quiz_end_commit_guard
run -all
puts "MODELSIM_CASE_COMPLETED 05_quiz_end_commit"
catch {quit -sim}
set lib [file join $out 06_uart_config_commit_work work]
file mkdir [file dirname $lib]
if {![file exists $lib]} {vlib $lib}
vmap work $lib
cd $root
set files [list [file join $root {src/uart_rx_byte.v}] [file join $root {src/uart_tx_byte.v}] [file join $root {src/welcome_uart_controller.v}] [file join $root {src/welcome_cfg_frame_commit.v}] [file join $root {src/emergency_cfg_frame_commit.v}] [file join $root {tb/tb_welcome_uart.v}]]
eval vlog -work work [list +incdir+$root/src +incdir+$root/audio_final/tb] $files
vsim -onfinish stop -t 1ps work.tb_welcome_uart
run -all
puts "MODELSIM_CASE_COMPLETED 06_uart_config_commit"
catch {quit -sim}
set lib [file join $out 07_meeting_control_work work]
file mkdir [file dirname $lib]
if {![file exists $lib]} {vlib $lib}
vmap work $lib
cd $root
set files [list [file join $root {src/meeting_ctrl.v}] [file join $root {sim/evidence/tb_meeting_ctrl_evidence.v}]]
eval vlog -work work [list +incdir+$root/src +incdir+$root/audio_final/tb] $files
vsim -onfinish stop -t 1ps work.tb_meeting_ctrl_evidence
run -all
puts "MODELSIM_CASE_COMPLETED 07_meeting_control"
catch {quit -sim}
set lib [file join $out 08_emergency_siren_work work]
file mkdir [file dirname $lib]
if {![file exists $lib]} {vlib $lib}
vmap work $lib
cd $root
set files [list [file join $root {audio_final/rtl/scene_audio_final.v}] [file join $root {sim/evidence/tb_siren_fast_evidence.v}]]
eval vlog -work work [list +incdir+$root/src +incdir+$root/audio_final/tb] $files
vsim -onfinish stop -t 1ps work.tb_siren_fast_evidence
run -all
puts "MODELSIM_CASE_COMPLETED 08_emergency_siren"
catch {quit -sim}
set lib [file join $out 09_audio_viz_clear_work work]
file mkdir [file dirname $lib]
if {![file exists $lib]} {vlib $lib}
vmap work $lib
cd $root
set files [list [file join $root {audio_final/rtl/audio_viz_overlay.v}] [file join $root {sim/tb/tb_audio_viz_scene_clear.v}]]
eval vlog -work work [list +incdir+$root/src +incdir+$root/audio_final/tb] $files
vsim -onfinish stop -t 1ps work.tb_audio_viz_scene_clear
run -all
puts "MODELSIM_CASE_COMPLETED 09_audio_viz_clear"
catch {quit -sim}
set lib [file join $out 10_bmp_multires_work work]
file mkdir [file dirname $lib]
if {![file exists $lib]} {vlib $lib}
vmap work $lib
cd $root
set files [list [file join $root {src/bmp_read_auto.v}] [file join $root {tb/tb_bmp_multires.v}]]
eval vlog -work work [list +incdir+$root/src +incdir+$root/audio_final/tb] $files
vsim -onfinish stop -t 1ps work.tb_bmp_multires
run -all
puts "MODELSIM_CASE_COMPLETED 10_bmp_multires"
catch {quit -sim}
set lib [file join $out 11_sd_bus_handoff_work work]
file mkdir [file dirname $lib]
if {![file exists $lib]} {vlib $lib}
vmap work $lib
cd $root
set files [list [file join $root {src/zone_launch.v}] [file join $root {src/audio_sd_arbiter.v}] [file join $root {sim/tb/tb_zone_launch.v}]]
eval vlog -work work [list +incdir+$root/src +incdir+$root/audio_final/tb] $files
vsim -onfinish stop -t 1ps work.tb_zone_launch
run -all
puts "MODELSIM_CASE_COMPLETED 11_sd_bus_handoff"
catch {quit -sim}
set lib [file join $out 12_ui_key_control_work work]
file mkdir [file dirname $lib]
if {![file exists $lib]} {vlib $lib}
vmap work $lib
cd $root
set files [list [file join $root {src/ui_key_ctrl.v}] [file join $root {tb/tb_ui_key_ctrl.v}]]
eval vlog -work work [list +incdir+$root/src +incdir+$root/audio_final/tb] $files
vsim -onfinish stop -t 1ps work.tb_ui_key_ctrl
run -all
puts "MODELSIM_CASE_COMPLETED 12_ui_key_control"
catch {quit -sim}
puts "MODELSIM_REPRESENTATIVE_RUN_COMPLETE"
