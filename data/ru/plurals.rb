{ :'ru' => { :i18n => { :plural => { :keys => [:one, :many, :other], :rule => lambda { |n| n = n.respond_to?(:abs) ? n.abs : ((m = n.to_s)[0] == "-" ? m[1,m.length] : m); (((v = n.to_s.split(".")[1]) ? v.length : 0) == 0 && n.to_i % 10 == 1 && n.to_i % 100 != 11) ? :one : ((((v = n.to_s.split(".")[1]) ? v.length : 0) == 0 && n.to_i % 10 == 0) || (((v = n.to_s.split(".")[1]) ? v.length : 0) == 0 && (5..9).include?(n.to_i % 10)) || (((v = n.to_s.split(".")[1]) ? v.length : 0) == 0 && (11..14).include?(n.to_i % 100))) ? :many : :other } } } } }