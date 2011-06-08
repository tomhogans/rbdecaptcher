require "lib/rbdecaptcher"

puts "DeCaptcher username: "
username = gets.chomp
puts "DeCaptcher password: "
password = gets.chomp

d = Decaptcher.new(username, password)

puts "\nProcessing...\n"

image = File.open("demo.jpeg", "rb")
image_data = image.read
image.close

result = d.solve image_data

puts "\nDeCaptcher result:"
p result
