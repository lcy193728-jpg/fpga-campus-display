[CmdletBinding()]
param(
    [string]$Iverilog = '',
    [string]$Vvp = '',
    [string]$OutputDirectory = 'sim/_evidence_full_iverilog',
    [switch]$ReusePassingLogs
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $Iverilog) { $Iverilog = (Get-Command iverilog -ErrorAction Stop).Source }
if (-not $Vvp) { $Vvp = (Get-Command vvp -ErrorAction Stop).Source }
$out = Join-Path $root $OutputDirectory
New-Item -ItemType Directory -Force -Path $out | Out-Null

# These cases are the maintained, current-specification RTL regressions.  Old
# display_score and other superseded presentation tests are intentionally not
# used as release criteria because their UI contracts were replaced by the
# full-screen ranking page and current OSD implementations.
$cases = @(
    @{ Name='video_first_frame_gate'; Top='tb_video_first_frame_gate'; Sources=@('src/video_first_frame_gate.v','sim/tb/tb_video_first_frame_gate.v') },
    @{ Name='sd_powerup_guard'; Top='tb_sd_powerup_guard'; Sources=@('src/sd_powerup_guard.v','sim/tb/tb_sd_powerup_guard.v') },
    @{ Name='spi_reset_idle'; Top='tb_spi_master_reset_idle'; Sources=@('src/sd_card/spi_master.v','sim/tb/tb_spi_master_reset_idle.v') },
    @{ Name='fat32_lookup'; Top='tb_fat32_lookup'; Sources=@('src/fat32_lookup.v','sim/tb/tb_fat32_lookup.v') },
    @{ Name='zone_launch'; Top='tb_zone_launch'; Sources=@('src/zone_launch.v','src/audio_sd_arbiter.v','sim/tb/tb_zone_launch.v') },
    @{ Name='audio_sd_arbiter'; Top='tb_audio_sd_arbiter'; Sources=@('src/audio_sd_arbiter.v','sim/tb/tb_audio_sd_arbiter.v') },
    @{ Name='audio_src_sel'; Top='tb_audio_src_sel'; Sources=@('audio_final/rtl/audio_src_sel.v','sim/tb/tb_audio_src_sel.v') },
    @{ Name='wav_stream_player'; Top='tb_wav_stream_player'; Sources=@('audio_final/rtl/wav_stream_player.v','sim/tb/tb_wav_stream_player.v') },
    @{ Name='audio_chain_e2e'; Top='tb_audio_chain_e2e'; Sources=@('audio_final/rtl/wav_stream_player.v','src/audio_sd_arbiter.v','audio_final/rtl/audio_src_sel.v','audio_board/rtl/audio_src_mux.v','sim/tb/tb_audio_chain_e2e.v') },
    @{ Name='audio_viz_gate'; Top='tb_audio_viz_gate'; Sources=@('audio_final/tb/EG_LOGIC_BRAM_sim.v','audio_final/rtl/audio_viz_overlay.v','audio_final/tb/tb_audio_viz_gate.v') },
    @{ Name='audio_viz_live_age'; Top='tb_audio_viz_live_age'; Sources=@('audio_final/tb/EG_LOGIC_BRAM_sim.v','audio_final/rtl/audio_viz_overlay.v','sim/tb/tb_audio_viz_live_age.v') },
    @{ Name='audio_viz_window_gate'; Top='tb_audio_viz_window_gate'; Sources=@('audio_final/rtl/audio_viz_overlay.v','sim/tb/tb_audio_viz_window_gate.v') },
    @{ Name='audio_viz_scene_clear'; Top='tb_audio_viz_scene_clear'; Sources=@('audio_final/rtl/audio_viz_overlay.v','sim/tb/tb_audio_viz_scene_clear.v') },
    @{ Name='bmp_scale'; Top='tb_bmp_scale'; Sources=@('audio_final/tb/EG_LOGIC_BRAM_sim.v','src/bmp_scale.v','tb/tb_bmp_scale.v') },
    @{ Name='bmp_scale_bram_gate'; Top='tb_bmp_scale_bram_gate'; Sources=@('audio_final/tb/EG_LOGIC_BRAM_sim.v','src/bmp_scale.v','sim/tb/tb_bmp_scale_bram_gate.v') },
    @{ Name='bmp_read_auto'; Top='tb_bmp_read_auto'; Sources=@('src/bmp_read_auto.v','tb/tb_bmp_read_auto.v') },
    @{ Name='bmp_2x_decim'; Top='tb_bmp_2x_decim'; Sources=@('src/bmp_read_auto.v','tb/tb_bmp_2x_decim.v') },
    @{ Name='bmp_multires'; Top='tb_bmp_multires'; Sources=@('src/bmp_read_auto.v','tb/tb_bmp_multires.v') },
    @{ Name='scene_selector'; Top='tb_scene_selector'; Sources=@('src/sim_modules/scene_selector.v','sim/tb/tb_scene_selector.v') },
    @{ Name='scene_load_guard'; Top='tb_scene_load_guard'; Sources=@('src/scene_load_guard.v','sim/tb/tb_scene_load_guard.v') },
    @{ Name='emergency_priority'; Top='tb_emergency_priority'; Sources=@('src/sim_modules/emergency_latch.v','src/sim_modules/priority_scheduler.v','sim/tb/tb_emergency_priority.v') },
    @{ Name='quiz_arbiter_4ch'; Top='tb_quiz_arbiter_4ch'; Sources=@('src/sim_modules/quiz_arbiter_4ch.v','sim/tb/tb_quiz_arbiter_4ch.v') },
    @{ Name='quiz_ctrl'; Top='tb_quiz_ctrl'; Sources=@('src/scene_control.v','src/quiz_ctrl.v','sim/tb/tb_quiz_ctrl.v') },
    @{ Name='quiz_key_chain'; Top='tb_quiz_key_chain'; Sources=@('src/sim_modules/key_sync_debounce.v','src/sim_modules/key_edge_detect.v','src/sim_modules/quiz_arbiter_4ch.v','sim/tb/tb_quiz_key_chain.v') },
    @{ Name='quiz_entry_audio_gate'; Top='tb_quiz_entry_audio_gate'; Sources=@('audio_final/rtl/audio_feature_events.v','audio_final/rtl/scene_audio_final.v','sim/tb/tb_quiz_entry_audio_gate.v'); RunDirectory='audio_final/tb' },
    @{ Name='quiz_end_commit_guard'; Top='tb_quiz_end_commit_guard'; Sources=@('src/quiz_end_commit_guard.v','sim/tb/tb_quiz_end_commit_guard.v') },
    @{ Name='quiz_ranking'; Top='tb_quiz_ranking'; Sources=@('src/display_adjust.v','sim/tb/tb_quiz_ranking.v') },
    @{ Name='quiz_timer'; Top='tb_quiz_timer'; Sources=@('src/sim_modules/quiz_timer.v','sim/tb/tb_quiz_timer.v') },
    @{ Name='welcome_uart'; Top='tb_welcome_uart'; Sources=@('src/uart_rx_byte.v','src/uart_tx_byte.v','src/welcome_uart_controller.v','src/welcome_cfg_frame_commit.v','src/emergency_cfg_frame_commit.v','tb/tb_welcome_uart.v') },
    @{ Name='welcome_mosaic'; Top='tb_welcome_mosaic'; Sources=@('audio_final/tb/EG_LOGIC_BRAM_sim.v','src/welcome_mosaic.v','sim/tb/tb_welcome_mosaic.v') },
    @{ Name='welcome_scene_effects'; Top='tb_welcome_scene_effects_v2'; Sources=@('src/sim_modules/welcome_osd_overlay.v','src/sim_modules/scroll_text_ctrl.v','src/sim_modules/fade_transition_ctrl.v','src/sim_modules/brightness_adjust.v','sim/tb/tb_welcome_scene_effects_v2.v') },
    @{ Name='meeting_osd_equiv'; Top='tb_meeting_osd_logic_equiv'; Sources=@('src/meeting_osd.v','sim/tb/tb_meeting_osd_logic_equiv.v') },
    @{ Name='meeting_ctrl_evidence'; Top='tb_meeting_ctrl_evidence'; Sources=@('src/meeting_ctrl.v','sim/evidence/tb_meeting_ctrl_evidence.v') },
    @{ Name='meeting_osd'; Top='tb_meeting_osd'; Sources=@('src/meeting_osd.v','tb/tb_meeting_osd.v') },
    @{ Name='osd_engine'; Top='tb_osd_engine'; Sources=@('src/osd_engine.v','tb/tb_osd_engine.v') },
    @{ Name='osd_menu'; Top='tb_osd_menu'; Sources=@('src/osd_font_rom.v','src/osd_menu_aa_rom.v','src/osd_menu.v','tb/tb_osd_menu.v') },
    @{ Name='osd_scene'; Top='tb_osd_scene'; Sources=@('src/osd_font_rom.v','src/osd_scene.v','tb/tb_osd_scene.v') },
    @{ Name='osd_welcome'; Top='tb_osd_welcome'; Sources=@('src/osd_font_rom.v','src/osd_welcome.v','tb/tb_osd_welcome.v') },
    @{ Name='scene_control'; Top='tb_scene_control'; Sources=@('src/scene_control.v','tb/tb_scene_control.v') },
    @{ Name='ui_key_ctrl'; Top='tb_ui_key_ctrl'; Sources=@('src/ui_key_ctrl.v','tb/tb_ui_key_ctrl.v') },
    @{ Name='ui_key_ctrl_meeting'; Top='tb_ui_key_ctrl_meeting'; Sources=@('src/ui_key_ctrl.v','tb/tb_ui_key_ctrl_meeting.v') },
    @{ Name='display_adjust_labels'; Top='tb_display_adjust_labels'; Sources=@('src/display_adjust.v','sim/tb/tb_display_adjust_labels.v') },
    @{ Name='display_adjust'; Top='tb_display_adjust'; Sources=@('src/display_adjust.v','tb/tb_display_adjust.v') },
    @{ Name='display_contrast'; Top='tb_display_contrast'; Sources=@('src/display_adjust.v','tb/tb_display_contrast.v') },
    @{ Name='display_adjust_busy'; Top='tb_display_adjust_busy_handshake'; Sources=@('src/display_adjust.v','sim/tb/tb_display_adjust_busy_handshake.v') },
    @{ Name='display_adjust_commit'; Top='tb_display_adjust_end_commit'; Sources=@('src/display_adjust.v','sim/tb/tb_display_adjust_end_commit.v') },
    @{ Name='display_resinfo'; Top='tb_display_resinfo_persistent'; Sources=@('src/display_adjust.v','sim/tb/tb_display_resinfo_persistent.v') },
    @{ Name='emergency_arrows'; Top='tb_emergency_arrows'; Sources=@('audio_final/tb/EG_LOGIC_BRAM_sim.v','src/emergency_font_rom.v','src/emergency_big_font_rom.v','src/emergency_title_font_rom.v','src/emergency_multi_overlay.v','sim/tb/tb_emergency_arrows.v'); RunDirectory='audio_final/tb' },
    @{ Name='emergency_font64'; Top='tb_emergency_font_native64'; Sources=@('audio_final/tb/EG_LOGIC_BRAM_sim.v','src/emergency_big_font_rom.v','sim/tb/tb_emergency_font_native64.v'); RunDirectory='audio_final/tb' },
    @{ Name='emergency_alarm_ctrl'; Top='tb_emergency_alarm_ctrl'; Sources=@('src/emergency_alarm_ctrl.v','tb/tb_emergency_alarm_ctrl.v') },
    @{ Name='emergency_uart_ticker'; Top='tb_emergency_uart_ticker'; Sources=@('audio_final/tb/EG_LOGIC_BRAM_sim.v','src/emergency_font_rom.v','src/emergency_big_font_rom.v','src/emergency_title_font_rom.v','src/emergency_multi_overlay.v','tb/tb_emergency_uart_ticker.v'); RunDirectory='audio_final/tb' },
    @{ Name='scene_audio_meeting'; Top='tb_scene_audio_meeting'; Sources=@('audio_final/rtl/scene_audio_final.v','audio_final/tb/tb_scene_audio_meeting.v'); RunDirectory='audio_final/tb' },
    @{ Name='siren_fast_evidence'; Top='tb_siren_fast_evidence'; Sources=@('audio_final/rtl/scene_audio_final.v','sim/evidence/tb_siren_fast_evidence.v'); RunDirectory='audio_final/tb' },
    @{ Name='volume_scale_equiv'; Top='tb_volume_scale_equiv'; Sources=@('audio_final/tb/tb_volume_scale_equiv.v') },
    @{ Name='score_popup_equiv'; Top='tb_score_popup_equiv'; Sources=@('src/display_adjust.v','sim/tb/tb_score_popup_equiv.v') },
    @{ Name='key_sync_edge'; Top='tb_key_sync_edge'; Sources=@('src/sim_modules/key_sync_debounce.v','src/sim_modules/key_edge_detect.v','sim/tb/tb_key_sync_edge.v') }
)

$summary = [System.Collections.Generic.List[string]]::new()
$pass = 0
$fail = 0
foreach ($case in $cases) {
    $name = $case.Name
    $image = Join-Path $out "$name.vvp"
    $logFile = Join-Path $out "$name.log"
    if ($ReusePassingLogs -and (Test-Path -LiteralPath $logFile -PathType Leaf)) {
        $oldText = Get-Content -LiteralPath $logFile -Raw
        if ($oldText.Length -gt 0 -and $oldText -notmatch '\[FAIL\]|RESULT:\s*FAIL|TEST FAILED|FATAL|error:') {
            $pass++
            $line = "[PASS] $name"
            $summary.Add($line)
            Write-Host "$line (reused)"
            continue
        }
    }
    $paths = @($case.Sources | ForEach-Object { Join-Path $root $_ })
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $compile = (& $Iverilog -g2012 -I (Join-Path $root 'src') -I (Join-Path $root 'audio_final/tb') -s $case.Top -o $image @paths 2>&1 | Out-String)
    } finally { $ErrorActionPreference = $saved }
    if (Test-Path -LiteralPath $image -PathType Leaf) {
        $runDirectory = if ($case.RunDirectory) { Join-Path $root $case.RunDirectory } else { $root }
        Push-Location $runDirectory
        # -n converts Verilog $stop into $finish so legacy self-checking
        # benches cannot leave an unattended regression at an interactive
        # prompt after they have already printed PASS.
        try { $run = (& $Vvp -n $image 2>&1 | Out-String); $rc = $LASTEXITCODE }
        finally { Pop-Location }
    } else {
        $run = ''
        $rc = 2
    }
    $text = $compile + $run
    Set-Content -LiteralPath $logFile -Value $text -Encoding utf8
    $bad = ($rc -ne 0) -or ($text -match '\[FAIL\]|RESULT:\s*FAIL|TEST FAILED|FATAL|error:')
    if ($bad) {
        $fail++
        $line = "[FAIL] $name exit=$rc"
    } else {
        $pass++
        $line = "[PASS] $name"
    }
    $summary.Add($line)
    Write-Host $line
}
$summary.Add("TOTAL=$($pass + $fail) PASS=$pass FAIL=$fail")
Set-Content -LiteralPath (Join-Path $out 'summary.txt') -Value $summary -Encoding utf8
Write-Host $summary[$summary.Count - 1]
if ($fail -ne 0) { exit 1 }
