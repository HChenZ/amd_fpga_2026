# 打印 phys_opt_design 的 -force_replication_on_nets 语义（Vivado 2025.2）
puts "=========== HELP phys_opt_design ==========="
catch { help phys_opt_design } e1
puts "---- catch1: $e1"
catch { help -verbose phys_opt_design } e2
puts "---- catch2: $e2"
puts "=========== END ==========="
