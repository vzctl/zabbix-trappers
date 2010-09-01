#!/usr/bin/ruby
#
# Author: lex@realisticgroup.com (Alexey Lapitsky)
#

require 'rubygems'
require 'mysql'

MASTER = false
SLAVE = false
DEBUG = false
SLOWINNODB = true

SYSTEM = "mysql" + (DEBUG ? "-debug" : "")
DTIME = "/var/run/zabbix/zabbix_#{SYSTEM}.dtime"
AGENT_CONF = "/etc/zabbix/zabbix_agentd.conf"
MYSQL = "/usr/bin/mysql"
ZABBIX_SENDER = "zabbix_sender"

type = $*[0]
user = $*[1]
pass = $*[2]
cred = "-u#{user} -p#{pass}"

def value(a)
  return a if a.nil?
  return a.to_i if a.match(/^\d+$/)
  return a.to_f if a.match(/^[\d.]+$/)
  return a
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
  cmd = "#{ZABBIX_SENDER} -z #{@server} -p 10051 -s #{@host} -k #{SYSTEM}.#{var} -o #{val}"
  if DEBUG 
    puts "#{cmd}\n"
  else
    system("#{cmd} 2>&1 >> /dev/null")
  end
end

@host, @server = zabbix_config
connection = Mysql.new("localhost", user, pass, "")
@values = {}

connection.query("show global variables;").each_hash do |row|
  var, val = row["Variable_name"], row["Value"]
  @values[var] = value(val)
end

if SLOWINNODB
  # Global status variables we use:
  [ "Aborted_clients", "Aborted_connects", "Binlog_cache_disk_use", "Binlog_cache_use", "Bytes_received",
    "Bytes_sent", "Com_alter_db", "Com_alter_table", "Com_create_db", "Com_create_function",
    "Com_create_index", "Com_create_table", "Com_delete", "Com_drop_db", "Com_drop_function",
    "Com_drop_index", "Com_drop_table", "Com_drop_user", "Com_grant", "Com_insert", "Com_replace",
    "Com_revoke", "Com_revoke_all", "Com_select", "Com_update", "Connections", "Created_tmp_disk_tables",
    "Created_tmp_tables", "Handler_read_first", "Handler_read_key", "Handler_read_next",
    "Handler_read_prev", "Handler_read_rnd", "Handler_read_rnd_next", "Innodb_buffer_pool_read_requests",
    "Innodb_buffer_pool_reads", "Innodb_buffer_pool_wait_free", "Innodb_buffer_pool_write_requests",
    "Innodb_log_waits", "Innodb_log_writes", "Key_blocks_unused", "Key_read_requests", "Key_reads",
    "Key_write_requests", "Key_writes", "Max_used_connections", "Open_files", "Open_tables",
    "Opened_tables", "Qcache_free_blocks", "Qcache_free_memory", "Qcache_hits", "Qcache_inserts",
    "Qcache_lowmem_prunes", "Qcache_not_cached", "Qcache_queries_in_cache", "Qcache_total_blocks",
    "Questions", "Select_full_join", "Select_range", "Select_range_check", "Select_scan", "Slave_running",
    "Slow_launch_threads", "Slow_queries", "Sort_merge_passes", "Sort_range", "Sort_rows", "Sort_scan",
    "Table_locks_immediate", "Table_locks_waited", "Threads_cached", "Threads_connected",
    "Threads_created", "Threads_running", "Uptime" ].each do |var|
    connection.query("show global status like '#{var}';").each_hash do |row|
      @values[row["Variable_name"]] = value(row["Value"])
    end
  end
else
  connection.query("show global status;").each_hash do |row|
    @values[row["Variable_name"]] = value(row["Value"])
  end
end

if MASTER
  connection.query("show master status;").each_hash do |row|
    row.each do |key, val|
      key = "Master_Status_#{key}"
      @values[key] = value(val)
    end
  end
end

if SLAVE
  connection.query("show slave status;").each_hash do |row|
    row.each do |key, val|
      @values[key] = value(val)
    end
  end
end

@values['Available'] = 1

if type == "daily"
  if File.exists?(DTIME)
    diff = (Time.new - File.ctime(DTIME))/60/60/24
    if diff < 1
      puts "Skipping daily gathering\n" if DEBUG
      puts 1
      exit(0)
    end

    File.delete(DTIME)
  end

  File.open(DTIME, "w") { |f| f.puts "Ran at " + Time.new.strftime("%Y%m%dT%H%M%S") + "\n"}
elsif @values['Uptime'] < 600   # wait 10m before sending data after a restart
  puts 1
  exit(0)
else

  tosend = {
    'Available' => @values['Available'],
    'Last_Errno' => @values['Last_Errno'] ? @values['Last_Errno'] : 0,
    'Last_Error' => @values['Last_Error'] ? @values['Last_Error'] : "",

     # Binlog parameters
    'Binlog_cache_disk_use' => @values['Binlog_cache_disk_use'],
    'Binlog_cache_use' => @values['Binlog_cache_use'],

    'Questions' => @values['Questions'],
    'Com_insert' => @values['Com_insert'],
    'Com_select' => @values['Com_select'],
    'Com_update' => @values['Com_update'],
    'Bytes_received' => @values['Bytes_received'],
    'Bytes_sent' => @values['Bytes_sent'],
    'Select_full_join' => @values['Select_full_join'],
    'Select_scan' => @values['Select_scan'],
    'Slow_queries' => @values['Slow_queries'],
    'Total_rows_returned' => (@values['Handler_read_first'] + @values['Handler_read_key'] +
                              @values['Handler_read_next'] + @values['Handler_read_prev'] +
                              @values['Handler_read_rnd'] + @values['Handler_read_rnd_next'] +
                              @values['Sort_rows']),
    'Indexed_rows_returned' => (@values['Handler_read_first'] + @values['Handler_read_key'] +
                                @values['Handler_read_next'] + @values['Handler_read_prev']),
    'Sort_merge_passes' => @values['Sort_merge_passes'],
    'Sort_range' => @values['Sort_range'],
    'Sort_scan' => @values['Sort_scan'],
    'Total_sort' => @values['Sort_range'] + @values['Sort_scan'],
    'Joins_without_indexes' => @values['Select_range_check'] + @values['Select_full_join'],
    'Key_read_requests' => @values['Key_read_requests'],
    'Key_reads' => @values['Key_reads'],
    'Key_write_requests' => @values['Key_write_requests'],
    'Key_writes' => @values['Key_writes'],
	
    'Table_locks_immediate' => @values['Table_locks_immediate'],
    'Table_locks_waited' => @values['Table_locks_waited'],
    'Created_tmp_disk_tables' => @values['Created_tmp_disk_tables'],
    'Created_tmp_tables' => @values['Created_tmp_tables'],
    'Aborted_clients' => @values['Aborted_clients'],
    'Aborted_connects' => @values['Aborted_connects'],
    'Connections' => @values['Connections'],
    'Successful_connects' => @values['Connections'] - @values['Aborted_connects'],
    'Max_used_connections' => @values['Max_used_connections'],
    'Slow_launch_threads' => @values['Slow_launch_threads'],
    'Threads_cached' => @values['Threads_cached'],
    'Threads_connected' => @values['Threads_connected'],
    'Threads_created' => @values['Threads_created'],
    'Threads_created_rate' => @values['Threads_created'],
    'Threads_running' => @values['Threads_running']}

     # Sometimes, replication isn't reported if not enabled.  Test first before adding
  if MASTER && @values['Master_Status_File'] && @values['Master_Status_File'].length > 0 
                                # Replication information	
    tosend.merge({
                   'Master_Status_Position' => @values['Master_Status_Position'],
                   'Master_Status_File' => @values['Master_Status_File'],
                   'Master_Status_Binlog_Do_DB' => @values['Master_Status_Binlog_Do_DB'],
                   'Master_Status_Binlog_Ignore_DB' => @values['Master_Status_Binlog_Ignore_DB'],
                 })
  end

  if SLAVE && @values['Relay_Log_File'] && @values['Relay_Log_File'].length > 0
    tosend.merge({
                   'Master_Host' => @values['Master_Host'],
                   'Master_Log_File' => @values['Master_Log_File'],
                   'Master_Port' => @values['Master_Port'],
                   'Master_User' => @values['Master_User'],
                   'Read_Master_Log_Pos' => @values['Read_Master_Log_Pos'],
                   'Relay_Log_File' => @values['Relay_Log_File'],
                   'Relay_Log_Pos' => @values['Relay_Log_Pos'],
                   'Relay_Log_Space' => @values['Relay_Log_Space'],
                   'Relay_Master_Log_File' => @values['Relay_Master_Log_File'],
                   'Exec_Master_Log_Pos' => @values['Exec_Master_Log_Pos'],
                   'Slave_IO_Running' => @values['Slave_IO_Running'],
                   'Slave_IO_State' => @values['Slave_IO_State'],
                   'Slave_SQL_Running' => @values['Slave_SQL_Running'],
                   'Slave_running' => @values['Slave_IO_Running'] == "Yes" && @values['Slave_SQL_Running'] == "Yes" ? 1 : 0,
                   'Seconds_Behind_Master' => @values['Seconds_Behind_Master'],
                 })
  end
end

tosend.each do |key, val|
  zabbix_post(key, val)
end

puts 1
exit(0)
