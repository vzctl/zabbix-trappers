#!/usr/bin/ruby
#
# Author: lex@realisticgroup.com (Alexey Lapitsky)
#

AGENT_CONF = "/etc/zabbix/zabbix_agentd.conf"
ZABBIX_SENDER = "zabbix_sender"
COLUMNS = %w(major minor name rio rmerge rsect rticks wio wmerge wsect wticks running tot_ticks rq_ticks)
DEBUG = false

def iostat
  entries = {}
  IO.foreach('/proc/diskstats') do |line|
     entry = Hash[*COLUMNS.zip(line.strip.split(/\s+/).collect { |v| Integer(v) rescue v }).flatten]
     entries[entry['name']] = entry if entry['name'] =~ /^sd[a-z]$/
  end
  entries
end

def zabbix_config
  config = File.read(AGENT_CONF)
  host = config.match(/Hostname\s*=\s*(.*)/i)[1].split('.')[0]
  server = config.match(/Server\s*=\s*(.*)/i)[1]
  [host, server]
end

def zabbix_post(var, val)
  if val.is_a? String
    val = case val
          when "yes" then 1
          when "on" then 1
          when "no" then 0
          when "" then 0
          when "off" then 0
          else val
          end
  end
  val = '"' + val +'"' if val.is_a? String
  cmd = "#{ZABBIX_SENDER} -z #{@server} -p 10051 -s #{@host} -k diskstats[#{var}] -o #{val}"
  if DEBUG 
    puts "#{cmd}\n"
  else
    system("#{cmd} 2>&1 >> /dev/null")
  end
end

@host, @server = zabbix_config

iostat1 = iostat
sleep 1
iostat2 = iostat

@values = {}

iostat2.each do |devname, stats|
  @values["#{devname},util"] = (iostat2[devname]['tot_ticks']-iostat1[devname]['tot_ticks'])/1000.0
end

@values.each do |key, val|
  zabbix_post(key, val)
end

puts 1

exit(0)
