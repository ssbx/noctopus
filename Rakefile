require 'rubygems'
require 'rake'

#
# set dirs
#
ROOT       = Dir.pwd
REBAR_DIR  = File.join(ROOT, "src", "erlang")
ERLANG_DIR = File.join(ROOT, "src", "erlang", "sysmo")
JAVA_DIR   = File.join(ROOT, "src", "java")
GO_DIR     = File.join(ROOT, "src", "go")

#
# set wrappers
#
REBAR     = File.join(REBAR_DIR, "rebar")
GRADLE    = File.join(JAVA_DIR,  "gradlew")


#
# tasks
#
task :default => :rel

task :build do
  cd GO_DIR;     sh "go build pping.go"
  cd ERLANG_DIR; sh "#{REBAR} -r compile"
  cd JAVA_DIR;   sh "#{GRADLE} installDist"
end

task :clean do
  cd GO_DIR;     sh "go clean pping.go"
  cd ERLANG_DIR; sh "#{REBAR} -r clean"
  cd JAVA_DIR;   sh "#{GRADLE} clean"
  cd ROOT;       sh "#{REBAR} clean"
end

task :test do
  cd ERLANG_DIR; sh "#{REBAR} -r test"
  cd JAVA_DIR;   sh "#{GRADLE} test"
end

task :check do
  cd JAVA_DIR;   sh "#{GRADLE} check"
end

task :doc do
  cd ERLANG_DIR; sh "#{REBAR} -r doc"
  cd JAVA_DIR;   sh "#{GRADLE} doc"
end

task :rel => [:build] do
  cd ROOT; sh "#{REBAR} generate"
  install_pping_command()
  puts "Release ready!"
end

task :run => [:rel] do
  cd ROOT; sh "./sysmo/bin/sysmo console"
end


#
# pping special case
#
def install_pping_command()
  dst      = File.join(ROOT, "sysmo", "utils")
  win_src  = File.join(GO_DIR, "pping.exe")
  unix_src = File.join(GO_DIR, "pping")
  if File.exist?(win_src)
    puts "Install #{win_src}"
    FileUtils.copy(win_src,dst)
  elsif File.exist?(unix_src)
    puts "Install #{unix_src}"
    FileUtils.copy(unix_src,dst)
  end
end
