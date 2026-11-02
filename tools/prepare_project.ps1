$ErrorActionPreference='Stop'
$base=Split-Path -Parent $PSScriptRoot
$mirror=Join-Path $base 'build/portable_project'
New-Item -ItemType Directory -Path $mirror -Force | Out-Null
foreach($rel in @('src','al_ip','audio_final/rtl','audio_final/integrated','audio_board/rtl','audio_board/vendor','audio_board/integrated')) {
 $source=Join-Path $base $rel
 if(Test-Path -LiteralPath $source) {
  $target=Join-Path $mirror $rel
  New-Item -ItemType Directory -Path $target -Force | Out-Null
  foreach($entry in Get-ChildItem -LiteralPath $source) { Copy-Item -LiteralPath $entry.FullName -Destination $target -Recurse -Force }
 }
}
Copy-Item -LiteralPath (Join-Path $base 'top.adc') -Destination (Join-Path $mirror 'top.adc') -Force
$project=Join-Path $mirror 'pic_sdram_audio_final.al'
$text=[IO.File]::ReadAllText((Join-Path $base 'pic_sdram_audio_final.al'))
$escaped=[Security.SecurityElement]::Escape($mirror.Replace('\','/'))
$text=[regex]::Replace($text,'(<Project\b[^>]*\bPath=")[^"]*',('$1'+$escaped))
[IO.File]::WriteAllText($project,$text,(New-Object Text.UTF8Encoding($false)))
# Adapt only generated-build INIT_FILE paths. Canonical source and data are unchanged.
$font=Join-Path $mirror 'src/emergency_big_font_rom.v'
$fontText=[IO.File]::ReadAllText($font)
foreach($bank in 0..4) {
 $name="emergency_big_font_bank$bank.dat"
 $data=Join-Path $mirror "src/$name"
 if((Get-FileHash -LiteralPath $data -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath (Join-Path $base "src/$name") -Algorithm SHA256).Hash) { throw "Font data mismatch: $name" }
 $fontText=$fontText.Replace("../../src/$name",$data.Replace('\','/'))
}
[IO.File]::WriteAllText($font,$fontText,(New-Object Text.UTF8Encoding($false)))
Write-Host "Open this generated TD project: $project"
Write-Host 'Canonical RTL, font data, pin/timing constraints and delivered bitstream were not modified.'
