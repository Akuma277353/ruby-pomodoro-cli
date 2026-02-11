#!/usr/bin/env ruby
# Pomodoro + Focus Stats (Windows-friendly, no gems)
# Background timer via hidden PowerShell Start-Process
#
# Commands:
#   ruby pomo.rb start <minutes> [label]
#   ruby pomo.rb stop
#   ruby pomo.rb cancel
#   ruby pomo.rb status
#   ruby pomo.rb today
#   ruby pomo.rb stats
#
# Data files: pomo_sessions.json, pomo_active.json

require "json"
require "time"
require "rbconfig"

SESSIONS_FILE = "pomo_sessions.json"
ACTIVE_FILE   = "pomo_active.json"

def windows?
  (/mswin|mingw|cygwin/i.match?(RbConfig::CONFIG["host_os"]) rescue false) || (ENV["OS"] == "Windows_NT")
end

def load_json(path, default)
  return default unless File.exist?(path)
  JSON.parse(File.read(path))
rescue JSON::ParserError
  default
end

def save_json(path, obj)
  File.write(path, JSON.pretty_generate(obj))
end

def sessions
  load_json(SESSIONS_FILE, [])
end

def add_session(session)
  all = sessions
  all << session
  save_json(SESSIONS_FILE, all)
end

def active
  load_json(ACTIVE_FILE, nil)
end

def set_active(obj)
  if obj.nil?
    File.delete(ACTIVE_FILE) if File.exist?(ACTIVE_FILE)
  else
    save_json(ACTIVE_FILE, obj)
  end
end

def today_key
  Time.now.strftime("%Y-%m-%d")
end

def seconds_to_hhmmss(s)
  s = [s.to_i, 0].max
  h = s / 3600
  m = (s % 3600) / 60
  r = s % 60
  if h > 0
    format("%02d:%02d:%02d", h, m, r)
  else
    format("%02d:%02d", m, r)
  end
end

def beep!
  if windows?
    # Reliable Windows beep
    # frequency=900Hz, duration=250ms
    system("powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
           "-Command", "[console]::Beep(900,250)")
  else
    # Terminal bell fallback
    print "\a"
  end
end

def usage
  puts <<~TXT
    Pomodoro CLI (Ruby, Windows-friendly)

    Commands:
      ruby pomo.rb start <minutes> [label]   # starts background timer + returns immediately
      ruby pomo.rb status                    # shows remaining time
      ruby pomo.rb stop                      # stops early and saves
      ruby pomo.rb cancel                    # cancels without saving
      ruby pomo.rb today                     # today's total + sessions
      ruby pomo.rb stats                     # last 7 days totals

    Examples:
      ruby pomo.rb start 25 "ML2 quiz"
      ruby pomo.rb status
      ruby pomo.rb stop
      ruby pomo.rb today
      ruby pomo.rb stats
  TXT
end

def compute_remaining_seconds(act)
  started = Time.parse(act["start_iso"])
  planned_seconds = act["minutes_planned"].to_i * 60
  elapsed = (Time.now - started).to_i
  planned_seconds - elapsed
end

def finalize_active!(reason: "completed")
  act = active
  return false if act.nil?

  started = Time.parse(act["start_iso"])
  ended = Time.now
  duration_sec = (ended - started).to_i
  duration_sec = 0 if duration_sec < 0

  add_session({
    "start_iso" => act["start_iso"],
    "end_iso" => ended.iso8601,
    "seconds" => duration_sec,
    "minutes_planned" => act["minutes_planned"],
    "label" => act["label"],
    "ended_reason" => reason
  })

  set_active(nil)
  true
end

def spawn_background_autostop!(seconds_until_done, start_iso)
  return unless windows?

  script_path = File.expand_path($0)

  # Use single-quoted strings in PowerShell; escape any single quotes by doubling them.
  ps_script_path = script_path.gsub("'", "''")
  ps_start_iso = start_iso.gsub("'", "''")

  # Hidden background process:
  # - sleeps for N seconds
  # - calls: ruby "<script>" autostop "<start_iso>"
  cmd = <<~PS.strip
    Start-Process -WindowStyle Hidden -FilePath powershell -ArgumentList `
      '-NoProfile','-ExecutionPolicy','Bypass','-Command',`
      "Start-Sleep -Seconds #{seconds_until_done}; ruby '#{ps_script_path}' autostop '#{ps_start_iso}'"
  PS

  system("powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", cmd)
end

cmd = ARGV.shift

case cmd
when "start"
  minutes = (ARGV.shift || "").to_i
  label = ARGV.join(" ").strip
  label = "Focus" if label.empty?

  if minutes <= 0
    puts "Please provide minutes > 0."
    exit 1
  end

  if active
    puts "A session is already running. Run: ruby pomo.rb status or ruby pomo.rb stop"
    exit 1
  end

  start_time = Time.now
  start_iso = start_time.iso8601

  set_active({
    "start_iso" => start_iso,
    "minutes_planned" => minutes,
    "label" => label
  })

  puts "Started: #{label} (#{minutes} min)"
  puts "Tip: run `ruby pomo.rb status` anytime to see time left."

  # Background auto-stop (Windows)
  seconds_until_done = minutes * 60
  spawn_background_autostop!(seconds_until_done, start_iso)

when "status"
  act = active
  if act.nil?
    puts "No active session."
    exit 0
  end

  remaining = compute_remaining_seconds(act)

  if remaining <= 0
    # If time already passed, finalize now (so status always stays truthful)
    saved = finalize_active!(reason: "completed")
    if saved
      beep!
      puts "Time's up! Saved session: #{act["label"]}"
    else
      puts "No active session (already saved)."
    end
  else
    puts "Active: #{act["label"]}"
    puts "Planned: #{act["minutes_planned"]} min"
    puts "Time left: #{seconds_to_hhmmss(remaining)}"
  end

when "stop"
  act = active
  if act.nil?
    puts "No active session to stop."
    exit 0
  end

  finalize_active!(reason: "stopped_early")
  puts "Stopped and saved: #{act["label"]}"

when "cancel"
  act = active
  if act.nil?
    puts "No active session to cancel."
    exit 0
  end

  set_active(nil)
  puts "Cancelled (not saved): #{act["label"]}"

when "autostop"
  # Internal command called by background process:
  # ruby pomo.rb autostop "<start_iso>"
  expected_start_iso = (ARGV.shift || "").strip
  act = active
  exit 0 if act.nil?

  # Only finalize if it's the same session (prevents old timers from stopping a new session)
  if expected_start_iso != "" && act["start_iso"] != expected_start_iso
    exit 0
  end

  # If already finished/expired, finalize
  remaining = compute_remaining_seconds(act)
  if remaining <= 0
    finalize_active!(reason: "completed")
    beep!
  end

when "today"
  all = sessions
  today = today_key

  todays = all.select do |s|
    Time.parse(s["start_iso"]).strftime("%Y-%m-%d") == today
  end

  total_sec = todays.map { |s| s["seconds"].to_i }.sum
  total_min = total_sec / 60.0

  puts "Today (#{today}): #{total_min.round(1)} focused minutes"
  puts "-" * 50

  if todays.empty?
    puts "No sessions yet."
  else
    todays.each_with_index do |s, i|
      st = Time.parse(s["start_iso"]).strftime("%H:%M")
      en = Time.parse(s["end_iso"]).strftime("%H:%M")
      mins = (s["seconds"].to_i / 60.0).round(1)
      reason = s["ended_reason"] || "completed"
      puts "#{i + 1}. #{st}-#{en}  #{mins} min  | #{s["label"]}  (#{reason})"
    end
  end

when "stats"
  all = sessions
  days = 7

  totals = Hash.new(0)
  all.each do |s|
    day = Time.parse(s["start_iso"]).strftime("%Y-%m-%d")
    totals[day] += s["seconds"].to_i
  end

  puts "Last #{days} days:"
  puts "-" * 50
  (0...days).each do |i|
    day = (Time.now - i * 86_400).strftime("%Y-%m-%d")
    mins = (totals[day] / 60.0).round(1)
    puts "#{day}: #{mins} min"
  end

else
  usage
end
