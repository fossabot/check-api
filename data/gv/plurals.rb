{ :'gv' => { :i18n => { :plural => { :keys => [:one, :two, :few, :other], :rule => lambda { |n| n = n.respond_to?(:abs) ? n.abs : ((m = n.to_s)[0] == "-" ? m[1,m.length] : m); n.to_f % 10 == 1 ? :one : n.to_f % 10 == 2 ? :two : [0, 20, 40, 60].include?(n.to_f % 100) ? :few : :other } } } } }