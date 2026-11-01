# XSim custom runtime script. Stage the frozen vectors before time advances,
# log focused signals from time zero, run the original self-checking test,
# and preserve a view for screenshot/reopening. No DUT or TB changes.
set ise_root [file normalize [file join [file dirname [info script]] ../..]]
set ise_out [file join $ise_root build/local/pynq_puf3/ise_screenshot]
file mkdir $ise_out
set ise_vectors [file join $ise_root data/ascon/permutation.mem]
set ise_local_vectors [file normalize [file join [pwd] data/ascon/permutation.mem]]
if {$ise_local_vectors ne $ise_vectors} {
    file mkdir [file dirname $ise_local_vectors]
    file copy -force $ise_vectors $ise_local_vectors
}

create_wave_config ise_screenshot
set ise_signals {
    /tb_key_ise/dut/clk
    /tb_key_ise/dut/rst_n
    /tb_key_ise/dut/perm_start
    /tb_key_ise/dut/perm_p12
    /tb_key_ise/dut/mode_p12
    /tb_key_ise/dut/p_start
    /tb_key_ise/dut/perm_run
    /tb_key_ise/dut/perm_done
    /tb_key_ise/dut/perm_ack
    /tb_key_ise/dut/cancel
    /tb_key_ise/dut/perm_rst_n
    /tb_key_ise/dut/state
    /tb_key_ise/expected
    /tb_key_ise/checks
    /tb_key_ise/errors
}
foreach ise_signal $ise_signals {
    if {[llength [get_objects $ise_signal]] != 1} {error "Required waveform signal missing: $ise_signal"}
    log_wave [get_objects $ise_signal]
    if {[file tail $ise_signal] in {state expected}} {
        add_wave -radix hex $ise_signal
    } elseif {[file tail $ise_signal] in {checks errors}} {
        add_wave -radix unsigned $ise_signal
    } else {
        add_wave $ise_signal
    }
}
open_vcd [file join $ise_out ise_screenshot.vcd]
foreach ise_signal $ise_signals {log_vcd [get_objects $ise_signal]}
# Original TB normally finishes at 37390 ns; its own watchdog is 2 ms.
# This independent 50 us bound also catches premature/nonterminating runs.
run 50 us
flush_vcd
close_vcd
set ise_checks [get_value -radix unsigned /tb_key_ise/checks]
set ise_errors [get_value -radix unsigned /tb_key_ise/errors]
set ise_fp [open [file join $ise_out verdict.txt] w]
puts $ise_fp "checks=$ise_checks errors=$ise_errors time=[current_time]"
if {$ise_checks != 1502 || $ise_errors != 0} {
    puts $ise_fp "FAIL: expected the complete original test (1502 checks, zero errors)"
    close $ise_fp
    error "ISE screenshot regression failed or incomplete"
}
puts $ise_fp "PASS: original tb_key_ise completed all 1502 checks"
close $ise_fp
# Positions read back from this unchanged TB's VCD (times are ns).
# Zoom to 300..1800 ns for the first P8/P12 and delayed-ack transactions.
add_wave_marker -name P8_START 380 ns
add_wave_marker -name P8_DONE 495 ns
add_wave_marker -name P8_ACK 760 ns
add_wave_marker -name P12_START 1190 ns
add_wave_marker -name P12_DONE 1345 ns
add_wave_marker -name P12_ACK 1610 ns
add_wave_marker -name CANCEL 36760 ns
save_wave_config [file join $ise_out ise_screenshot.wcfg]
open_wave_config [file join $ise_root sim/ascon/ise_screenshot_view.wcfg]
puts "ISE_SCREENSHOT_PASS checks=$ise_checks errors=$ise_errors; artifacts=$ise_out"
