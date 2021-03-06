namespace :install do
  BOOTSTRAP_ACTS = [:ruby_stack, :actstore]
  BASE_ACTS = [:booth_support_stack, :database_stack, :web_stack, :booth, :postgres_tamer, :nginx_tamer]
  OPTIONAL_ACTS = [:erlang_stack, :java_web_stack, :python_stack, :static_web_stack]
  ACTS = BASE_ACTS + OPTIONAL_ACTS
  
  task :ensure_targets => :parse_args do
    fail "@deploy_target must have been set before using these .tasks" unless @deploy_target
    
    @circus_tool = File.expand_path("../../../circus/bin/circus", __FILE__) 
    @act_root ||= ENV['ACT_ROOT'] || 'http://repo.deployacircus.com/acts/current'
    @bootstrap_root ||= @act_root
    @circus_deb_cfg ||= "deb http://repo.deployacircus.com/debian highwire main"
  end

  # Placeholder task that allows installer implementations to connect root ssh
  task :ensure_root_ssh => :ensure_targets do
  end
  
  # Placeholder task that allows installer implementations to connect non-root ssh
  task :ensure_ssh => :ensure_targets do
  end
  
  task :ensure_arch => :ensure_ssh do
    @act_arch ||= ENV['ACT_ARCH'] || determine_arch
  end
  
  task :ensure_bootstrap_connection => :ensure_targets do
  end

  def determine_arch
    res = 'i386'
    @ssh.execute do |ssh|
      res = case ssh.exec!("uname -m").strip
        when "x86_64" then "x64"
        else "i386"
      end
    end
    res
  end

  # Applies the current architecture to an act name, if required
  def act_name_with_arch(name)
    if name.to_s.end_with? 'stack' then name else "#{name}-#{@act_arch}" end
  end
  
  desc "Installs the Clown onto the deployment target"
  task :clown => [:ensure_root_ssh] do
    @root_ssh.execute do |ssh|
      log_remote_cmd(ssh, "sudo apt-get remove clown --purge -y --force-yes")
      log_remote_cmd(ssh, "sudo sh -c 'echo \"#{@circus_deb_cfg}\" >/etc/apt/sources.list.d/clown-local.list'")
      log_remote_cmd(ssh, "sudo apt-get update")
      log_remote_cmd(ssh, "sudo apt-get install clown -y --force-yes")
      log_remote_cmd(ssh, "sudo start svscan")
    end
  end
  
  BOOTSTRAP_ACTS.each do |name|
    task name => [:ensure_targets, :ensure_bootstrap_connection, :ensure_arch] do
      act_fn = act_name_with_arch(name)
      sh "#{@circus_tool} deploy #{@deploy_target} #{name} #{@bootstrap_root}/#{act_fn}.act"
    end
  end
  task :bootstrap => BOOTSTRAP_ACTS
  
  ACTS.each do |name|
    task name => [:ensure_targets, :ensure_arch] do
      act_fn = act_name_with_arch(name)
      sh "#{@circus_tool} deploy #{@deploy_target} #{name} #{@act_root}/#{act_fn}.act"
    end
  end
  task :base_acts => BASE_ACTS
  task :optional_acts => OPTIONAL_ACTS
  
  task :acts => [:bootstrap, :base_acts, :optional_acts]
  task :all => [:clown, :acts]
  task :all_basic => [:clown, :bootstrap, :base_acts]
  
  task :build_host => [:clown, :bootstrap, :booth_support_stack, :booth]
end

def log_remote_cmd(ssh, cmd)
  puts cmd
  
  ssh.exec!(cmd) do |channel, stream, data|
    STDOUT << data if stream == :stdout
    STDERR << data if stream == :stderr
  end
end