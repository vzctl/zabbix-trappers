#!/bin/env ruby
#
# Author: lex@realisticgroup.com Alexey Lapitsky
#

require 'socket'

AGENT_CONF = "/etc/zabbix/zabbix_agentd.conf"
ZABBIX_SENDER = "zabbix_sender"
SOCKET =  "/var/run/haproxy.stat"
DEBUG = false
COLUMNS = %w(pxname svname qcur qmax scur smax slim stot bin bout dreq dresp ereq econ eresp wretr wredis status weight act bck chkfail chkdown lastchg downtime qlimit pid iid sid throttle lbtot tracked type rate rate_lim rate_max check_status check_code check_duration hrsp_1xx hrsp_2xx hrsp_3xx hrsp_4xx hrsp_5xx hrsp_other hanafail req_rate req_rate_max req_tot cli_abrt srv_abrt)
REPORT_COLUMNS = %w(scur stot)

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
  cmd = "#{ZABBIX_SENDER} -z #{@server} -p 10051 -s #{@host} -k haproxy[#{var}] -o #{val}"
  if DEBUG 
    puts "#{cmd}\n"
  else
    system("#{cmd} 2>&1 >> /dev/null")
  end
end

@host, @server = zabbix_config

socket = UNIXSocket.open(SOCKET)
socket.write("show stat\n")
socket_data = socket.read
socket.close

@values = {}

entries = []
socket_data.each_line do |line|
  next if line =~ /^#/ || line.size < 10
  entry = Hash[*COLUMNS.zip(line.strip.split(/\,/).collect { |v| Integer(v) rescue v }).flatten]
  entries  << entry
end

entries.each do |entry|
  REPORT_COLUMNS.each do |col|
    @values["#{entry['pxname']}:#{entry['svname']},#{col}"] = entry[col]
  end
end

@values.each do |key, val|
  zabbix_post(key, val)
end

puts 1

exit(0)
