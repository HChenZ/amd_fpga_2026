param(
    [string]$TemplatePath = 'F:\2026嵌入式大赛FPGA\海报\参考模板\AMD_poster_template.pptx',
    [string]$OutputDir = $PSScriptRoot
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$TemplatePath = (Resolve-Path -LiteralPath $TemplatePath).Path
$OutputDir = [IO.Path]::GetFullPath($OutputDir)
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$benchRel = 'data/pynq/notebook_20261031_112052/pynq_warm_benchmark.json'
$gateRel = 'data/pynq/error_gate_20261031_112812/pynq_board_error_gate.json'
$bench = Get-Content -Raw -Encoding utf8 (Join-Path $repo $benchRel) | ConvertFrom-Json
$gate = Get-Content -Raw -Encoding utf8 (Join-Path $repo $gateRel) | ConvertFrom-Json
if ($bench.service.simulated -or $gate.board_validation -ne 'PASS') { throw 'Real-board evidence required' }
$enc = @($bench.modes.sw.encrypt.summary.median, $bench.modes.hw.encrypt.summary.median, $bench.modes.ise.encrypt.summary.median)
$dec = @($bench.modes.sw.decrypt.summary.median, $bench.modes.hw.decrypt.summary.median, $bench.modes.ise.decrypt.summary.median)
$speeds = @(($enc[0]/$enc[1]), ($enc[0]/$enc[2]))
function Num($n) { return ([double]$n).ToString('N0', [cultureinfo]'en-US') }
function Ratio($n) { return ([double]$n).ToString('F3', [cultureinfo]'en-US') }
function Color($r,$g,$b) { return [int]($r + 256*$g + 65536*$b) }
$black=Color 20 20 20; $dark=Color 48 48 48; $gray=Color 93 93 93
$red=Color 192 0 0; $white=Color 255 255 255; $light=Color 244 244 244
function Box($name,$x,$y,$w,$h,$fill,$stroke=$null,$round=$false) {
    $kind=1; if($round){$kind=5}
    $s=$script:slide.Shapes.AddShape($kind,$x,$y,$w,$h);$s.Name=$name
    $s.Fill.ForeColor.RGB=$fill
    if($null -eq $stroke){$s.Line.Visible=0}else{$s.Line.ForeColor.RGB=$stroke;$s.Line.Weight=0.8}
    return $s
}
function Text($name,$value,$x,$y,$w,$h,$size=11,$bold=$false,$color=$black,$align=1,$font='Microsoft YaHei') {
    $s=$script:slide.Shapes.AddTextbox(1,$x,$y,$w,$h);$s.Name=$name
    $s.TextFrame.MarginLeft=0;$s.TextFrame.MarginRight=0;$s.TextFrame.MarginTop=0;$s.TextFrame.MarginBottom=0
    $s.TextFrame.WordWrap=-1;$s.TextFrame.AutoSize=0
    $t=$s.TextFrame.TextRange;$t.Text=$value;$t.Font.Name=$font;$t.Font.NameFarEast='Microsoft YaHei'
    $t.Font.Size=[int][Math]::Round($size);$t.Font.Bold=[int](-1*[int]$bold);$t.Font.Color.RGB=$color
    $t.ParagraphFormat.Alignment=$align;$t.ParagraphFormat.SpaceAfter=3
    $s.TextFrame2.AutoSize=0
    $s.Width=[single]$w;$s.Height=[single]$h
    return $s
}
function Line($name,$x1,$y1,$x2,$y2,$arrow=$false) {
    $s=$script:slide.Shapes.AddLine($x1,$y1,$x2,$y2);$s.Name=$name
    $s.Line.ForeColor.RGB=$dark;$s.Line.Weight=0.9
    if($arrow){$s.Line.EndArrowheadStyle=3}
    return $s
}
function Node($name,$label,$x,$y,$w,$h,$fill=$white,$size=10) {
    $null=Box $name $x $y $w $h $fill $gray
    $null=Text ($name+'-label') $label ($x+3) ($y+4) ($w-6) ($h-7) $size $true $black 2
}
$app=New-Object -ComObject PowerPoint.Application
try {
    $deck=$app.Presentations.Open($TemplatePath,-1,0,0)
    if($deck.Slides.Count -ne 1 -or $deck.PageSetup.SlideWidth -ne 960 -or $deck.PageSetup.SlideHeight -ne 540){throw 'Unexpected source template'}
    $script:slide=$deck.Slides.Item(1)
    # Retain the template's three divider lines and its original AMD logo.
    for($i=$slide.Shapes.Count;$i -ge 1;$i--){if($slide.Shapes.Item($i).Id -notin @(12,13,14,39)){$slide.Shapes.Item($i).Delete()}}
    foreach($design in $deck.Designs){
        foreach($masterShape in $design.SlideMaster.Shapes){
            if($masterShape.HasTextFrame -eq -1 -and $masterShape.TextFrame.TextRange.Text -match 'Copyright'){
                $masterShape.TextFrame.TextRange.Text='华南理工大学  2026'
                $masterShape.TextFrame.TextRange.Font.Name='Microsoft YaHei'
                $masterShape.TextFrame.TextRange.Font.Size=8
                $masterShape.TextFrame.TextRange.Font.Color.RGB=$gray
            }
        }
    }
    $null=Text 'project-title' "RISC-V 轻量级密码 SoC`rAscon-AEAD128 指令扩展与 FPGA 验证" 24 28 445 58 22 $true
    $null=Text 'team' '熊雅琦   胡潇正   黄晨中' 516 18 264 22 12 $true $black 2
    $null=Text 'university' '华南理工大学' 552 43 223 23 15 $true $black 2
    $null=Text 'subtitle' 'RISC-V Lightweight Cryptography SoC with ASCON ISE' 24 11 438 14 9 $false $gray 1 'Calibri'
    $null=$slide.Shapes.AddPicture((Join-Path $repo 'docs/tech_report/figs/board_photo.jpg'),0,-1,817,9,125,93.75)
    $null=Text 'board-header' "正点原子领航者 ZYNQ7020`rxc7z020clg400-1 / PYNQ 2.7" 790 112 154 32 9 $true $black 2
    $null=Box 'intro-header' 24 91 273 31 $dark
    $null=Text 'intro-heading' 'INTRODUCTION / 项目简介' 29 96 263 24 15 $true $white 2 'Calibri'
    $null=Text 'intro-copy' "面向嵌入式短消息认证加密，复用自研五级`rRISC-V CPU，在同一平台比较纯软件、`rMMIO 加速器与定制指令扩展（ISE）。`r算法以 NIST SP 800-232 Final 为基准。" 24 135 273 68 11
    # Real repository photo, proportional and uncropped.
    $null=$slide.Shapes.AddPicture((Join-Path $repo 'docs/tech_report/figs/board_photo.jpg'),0,-1,27,211,267,200.25)
    $null=Text 'board-caption' '实物平台：PS 运行 PYNQ，PL 运行 RV32 SoC' 24 417 273 18 9.5 $true $black 2
    $null=Text 'scope-heading' '当前交付范围' 24 445 273 20 12 $true
    $null=Text 'scope-copy' "RV32IM + Zicsr，五级流水线与 I/D Cache`rPT / AD 各 0–16 B，Key / Nonce / Tag 各 16 B`r三种模式共用输入、黄金参考与测量边界" 24 472 273 48 10.5
    $null=Text 'architecture-heading' 'SYSTEM ARCHITECTURE / 系统架构' 326 91 269 22 12 $true $black 2 'Calibri'
    Node 'host' 'PYNQ / Jupyter 黄金参考与展示' 328 120 265 25 $light 10
    $null=Line 'host-ps' 460 145 460 155 $true
    Node 'ps' 'Zynq PS：Python API' 328 155 265 25
    $null=Line 'ps-link' 460 180 460 190 $true
    Node 'mailbox' 'AXI-Lite FIFO / UART mailbox' 328 190 265 25 $light
    $null=Line 'link-cpu' 460 215 460 225 $true
    Node 'cpu' 'PL：五级 RV32 CPU + mcycle' 328 225 265 25
    $null=Line 'cpu-sw' 369 250 369 261 $true
    $null=Line 'cpu-mmio' 460 250 460 261 $true
    $null=Line 'cpu-ise' 551 250 551 261 $true
    Node 'sw' 'SW 软件' 328 261 82 25 $light
    Node 'mmio' 'HW / MMIO' 419 261 83 25 $light
    Node 'ise' 'ISE 置换' 511 261 82 25 $light
    $null=Text 'architecture-foot' 'CPU 周期与 PS 调用墙钟分别记录' 328 290 265 16 9 $false $gray 2
    $null=Box 'creative-vertical' 609 165 32 351 $dark
    $null=Text 'creative-label' "C`rR`rE`rA`rT`rI`rV`rE`r`rD`rE`rS`rI`rG`rN" 613 174 24 332 15 $true $white 2 'Calibri'
    $null=Box 'ise-panel' 328 319 265 99 $white $black $true
    $null=Text 'ise-heading' '创新一  面向置换热点的指令扩展' 340 329 243 20 11.5 $true $red
    $null=Text 'ise-copy' "custom-0 编码，320-bit 专用状态寄存器`r4 条指令：状态写入、读出及 P8 / P12`rinline assembly 调用，无需修改 GCC 后端`r在同一 RV32 上验证标准正确性与周期收益" 340 354 243 57 10.5
    $null=Box 'evidence-panel' 328 431 265 88 $white $black $true
    $null=Text 'evidence-heading' '创新二  可复查的 PYNQ 演示流程' 340 441 243 20 11.5 $true $red
    $null=Text 'evidence-copy' "bit / hwh / 固件哈希绑定，KAT 与原始周期归档`r通用 pynq-overlay-workflow Skill 已实现`rL3 实板验证覆盖 Ascon、GPIO 与 DMA 回环" 340 466 243 45 10.3
    $null=Box 'results-vertical' 670 162 30 129 $dark
    $null=Text 'results-label' "R`rE`rS`rU`rL`rT" 674 166 22 125 15 $true $white 2 'Calibri'
    $null=Text 'speed-mmio' ((Ratio $speeds[0])+'×') 711 167 117 33 27 $true $red 1 'Calibri'
    $null=Text 'speed-ise' ((Ratio $speeds[1])+'×') 832 167 111 33 27 $true $black 1 'Calibri'
    $null=Text 'speed-mmio-label' 'MMIO 加密周期加速' 711 205 118 17 9.2 $true
    $null=Text 'speed-ise-label' 'ISE 加密周期加速' 832 205 111 17 9.2 $true
    $null=Text 'chart-title' '加密中位周期（越短越快）' 711 231 231 17 10 $true
    $labels=@('SW','MMIO','ISE');$fills=@($gray,$red,$dark)
    for($j=0;$j -lt 3;$j++){
        $y=254+$j*17
        $null=Text ('bar-label-'+$j) $labels[$j] 711 $y 36 15 9 $false $black 1 'Calibri'
        $barw=142*$enc[$j]/$enc[0]
        $null=Box ('cycles-bar-'+$j) 749 ($y+2) $barw 8 $fills[$j]
        $null=Text ('bar-value-'+$j) (Num $enc[$j]) (754+$barw) ($y-1) 46 16 9 $true $black 1 'Calibri'
    }
    $null=Text 'benchmark-conditions' "官方 KAT #529：PT=16 B / AD=0`r每档预热 5 次，采样 30 次，统计中位数" 684 313 259 30 9 $false $gray
    $tbl=$slide.Shapes.AddTable(4,4,684,350,259,77);$tbl.Name='editable-benchmark-table'
    $rows=@(@('模式','加密 cycles','解密 cycles','解密加速比'),@('SW',(Num $enc[0]),(Num $dec[0]),'1.000×'),@('MMIO',(Num $enc[1]),(Num $dec[1]),((Ratio ($dec[0]/$dec[1]))+'×')),@('ISE',(Num $enc[2]),(Num $dec[2]),((Ratio ($dec[0]/$dec[2]))+'×')))
    for($r=1;$r -le 4;$r++){for($c=1;$c -le 4;$c++){
        $cell=$tbl.Table.Cell($r,$c).Shape;$cell.TextFrame.TextRange.Text=[string]$rows[$r-1][$c-1]
        $cell.TextFrame.MarginLeft=2;$cell.TextFrame.MarginRight=2;$cell.TextFrame.MarginTop=2;$cell.TextFrame.MarginBottom=1
        $cell.TextFrame.TextRange.Font.Name='Microsoft YaHei';$cell.TextFrame.TextRange.Font.Size=9
        $cell.TextFrame.TextRange.ParagraphFormat.Alignment=2
        if($r -eq 1){$cell.Fill.ForeColor.RGB=$dark;$cell.TextFrame.TextRange.Font.Color.RGB=$white;$cell.TextFrame.TextRange.Font.Bold=-1}
        else{$cell.Fill.ForeColor.RGB=$white;$cell.TextFrame.TextRange.Font.Color.RGB=$black}
    }}
    $null=Text 'validation' "实板：三模式各 289 组容量内 KAT / 坏 Tag 拒绝`r错误恢复 9/9 项通过，reset / epoch 恢复 7/7" 684 438 259 33 9.5 $true
    $null=Text 'implementation' "实现报告：100 MHz 配置，WNS +0.034 ns`rLUT 14,269 / FF 19,691 / BRAM 34.5 / DSP 4" 684 475 259 29 9.1
    $null=Text 'limits' '周期不含 PS/UART；主线频率与跨上电稳定性未测' 684 505 259 12 7.6 $false $gray
    $notes=@"
任务 D03 海报，owner TBD，材料日期 2026-11-01。
学校与成员由本轮用户明确提供；不填写指导老师。
仓库依据：c05782d；测量固件/bitstream 身份以原始 JSON 的 release 哈希为准，不称本次材料提交重新上板。
性能原始数据：$benchRel
测量范围：firmware AEAD mcycle，排除 PS/UART。KAT #529，PT 16B、AD 0，预热5次、30次采样。
错误恢复原始证据：$gateRel
三模式容量内 289 KAT 与坏 Tag：data/pynq/notebook_20261031_112052/pynq_board_smoke.json。当前板端只声明 PT/AD 0..16B，不称 1089 组板测。
架构与四条指令：docs/tech_report/report.md §2.3.3.4；src/firmware/pynq_svc/svc.h。
资源/时序：docs/tech_report/report.md §2.3.3.9、附录中的原始实现报告。Vivado2025.2，pynq_wrapper，xc7z020clg400-1。配置100MHz不等于测得Fmax。原始普通 Warning 非零。
Skill L3：data/skill/l3_20261031_063709/40_summary.json，Ascon/GPIO/DMA 实板 PASS；不宣称跨平台普适。
照片：docs/tech_report/figs/board_photo.jpg，仓库真实实物图片。
标准依据沿用仓库锁定的 NIST Final 基准，没有另作规则推断。
独立 PUF 扩展不混入本海报主线性能；其 RO 时序/跨上电可靠性仍未验收。
模板仅作设计参考。保留960x540点画布、AMD标识、分区线、三栏组织；中文使用Microsoft YaHei，英文辅助用Calibri。
"@
    $slide.NotesPage.Shapes.Placeholders.Item(2).TextFrame.TextRange.Text=$notes
    $pptx=Join-Path $OutputDir 'ascon_soc_poster.pptx'
    $deck.SaveAs($pptx,24)
    $slide.Export((Join-Path $OutputDir 'ascon_soc_poster.png'),'PNG',2400,1350)
    $audit=@{tool='Microsoft PowerPoint COM';version=$app.Version;slides=$deck.Slides.Count;width_pt=$deck.PageSetup.SlideWidth;height_pt=$deck.PageSetup.SlideHeight;template_sha256=(Get-FileHash -LiteralPath $TemplatePath -Algorithm SHA256).Hash.ToLower();benchmark_source=$benchRel;benchmark_sha256=(Get-FileHash (Join-Path $repo $benchRel)).Hash.ToLower();gate_source=$gateRel;enc_cycles=$enc;dec_cycles=$dec;shapes=$slide.Shapes.Count;native_tables=1;output_sha256=(Get-FileHash $pptx).Hash.ToLower()}
    $audit|ConvertTo-Json -Depth 5|Set-Content -Encoding utf8 (Join-Path $OutputDir 'validation.json')
    $fit=@()
    foreach($shape in $slide.Shapes){
        if($shape.HasTextFrame -eq -1 -and $shape.TextFrame.HasText -eq -1){
            $bound=$shape.TextFrame.TextRange.BoundHeight
            if($bound -gt ($shape.Height+1)){$fit+=@{name=$shape.Name;height_pt=$shape.Height;bound_height_pt=$bound}}
        }
    }
    @{tool='PowerPoint 16 COM TextRange.BoundHeight';overflow_count=$fit.Count;findings=$fit}|ConvertTo-Json -Depth 5|Set-Content -Encoding utf8 (Join-Path $OutputDir 'text_fit.json')
    $deck.Close()
    Write-Output ('Created '+$pptx)
} finally { $app.Quit() }
