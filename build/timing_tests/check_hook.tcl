# 钩子模板实例化的冒烟检查（不跑综合，约 20 s）
#   vivado -mode batch -source build/timing_tests/check_hook.tcl -notrace
set root [file normalize [file join [file dirname [info script]] ../..]]
set tmpl [file join $root build timing_tests hooks rep_hook.tmpl]
set fh [open $tmpl r]; set body [read $fh]; close $fh
set cases [list \
    [list 400 "*u_crypto_aead/state*" 128 1] \
    [list 128 "*u_crypto_aead/state* *id_ex_u/sel_*" 128 1] \
    [list 400 "*u_crypto_aead/state*" 128 0]]
set i 0
foreach c $cases {
    incr i
    lassign $c fo pats mf dorep
    set out [string map [list "@@FO_MIN@@" $fo "@@PATS@@" $pats "@@MAXFAN@@" $mf "@@DOREP@@" $dorep] $body]
    set ok [info complete $out]
    puts "CASE $i fo=$fo maxfan=$mf dorep=$dorep complete=$ok bytes=[string length $out]"
    if {!$ok} { puts "CASE $i FAILED: unbalanced braces" }
    # 关键：替换后不应残留占位符，且 pats 列表元素数应为预期
    if {[string match "*@@*" $out]} { puts "CASE $i FAILED: leftover placeholder" }
    set probe [join [lrange [split $out "\n"] 12 14] " | "]
    puts "   head: $probe"
}
puts "CHECK_HOOK DONE"
