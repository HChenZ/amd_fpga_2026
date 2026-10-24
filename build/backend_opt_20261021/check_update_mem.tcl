puts "CHECK catch=[catch {help update_mem} e]"
puts "CHECK err=$e"
if {![string match "*invalid*" $e] && ![string match "*unknown*" $e]} { puts "CHECK update_mem=AVAILABLE" } else { puts "CHECK update_mem=MISSING" }
