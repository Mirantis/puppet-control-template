#!/usr/bin/env ruby

require 'timeout'
require 'optparse'
require 'ostruct'
require 'pp'
require 'yaml'
require 'json'

# Setup application_tier so hiera data can be loaded properly
ENV['FACTER_application_tier'] = 'openstack'

#######################################
#### Functions and config. See the ####
#### bottom for where we actually #####
#### end up calling everything.   #####
#######################################

def lock
  # Get an exclusive lock on our lockfile to prevent multiple copies of this script from running
  lockfile = File.open('/var/run/pmlc.lock', File::RDWR|File::CREAT, 0644)
  Timeout::timeout(0.001) { lockfile.flock(File::LOCK_EX) } rescue nil
end

def setup_eyaml(verbose)
  setup_eyaml      = %Q(dockerctl shell astute mco rpc execute_shell_command execute cmd="puppet resource package hiera-eyaml ensure='present' | tee -a /var/log/pmlc.log")
  setup_deep_merge = %Q(dockerctl shell astute mco rpc execute_shell_command execute cmd="puppet resource package deep_merge ensure='present' | tee -a /var/log/pmlc.log")
  if $?.exitstatus != 0
    wet_the_bed("Could not setup hiera-eyaml and deep_merge. Cannot continue")
  end

  if verbose == true
    puts "\ndebug:\n#{setup_eyaml}"
    puts "\ndebug:\n#{setup_deep_merge}"
  end

  puts "\nhiera-eyaml and deep_merge gems installed."
end

def setup_git(verbose)
  install_git = `puppet resource package git ensure='present'`
  if $?.exitstatus != 0
    wet_the_bed("Git could not be installed. Cannot continue")
  end

  if verbose == true
    puts "\ndebug:\n#{install_git}"
  end

  puts "\nGit is installed."

end


def wet_the_bed(msg)
  # Generic error function.
  puts msg
  exit 1
end

# Get a lock or exit
lock or wet_the_bed("Failed to get an exclusive lock on /var/run/pmlc.lock. Is this already running?")

# Load our repo information from yaml file
@repos  = YAML.load_file('./repos.yaml')
@roles  = YAML.load_file('./roles.yaml')
@config = YAML.load_file('./config.yaml')

def directory_exists?(directory)
  File.directory?(directory)
end

def setup_repos(verbose, clone)
  # Configure the various repos we'll be using

  # Perform a git pull on each repo
  @repos.keys.each do |repo|
    remote   = @repos["#{repo}"]['remote']
    location = @repos["#{repo}"]['location']
    cmd      = "cd #{location} ; git pull"

    if verbose == true
      puts "\ndebug: remote   = #{remote}"
      puts "debug: location = #{location}"
      puts "debug: cmd      = #{cmd}\n"
    end

    # Checkout the repo if it doesn't exist
    unless directory_exists?("#{location}")
      puts "\nDirectory #{location} does not exist. Cloning repo\n"
      clone_cmd  = "git clone #{remote} #{location}"
      if verbose == true
        puts "debug: clone_cmd = #{clone_cmd}"
        puts "debug: Executing: #{clone_cmd}" 
      end
      clone_repo = system("#{clone_cmd}")
    end

    # Ensure the repo is up to date
    puts "Updating repo #{repo}"

    if verbose == true
      puts "debug: Executing: #{cmd}"
    end

    update_repo = system("#{cmd}")
    if $?.exitstatus != 0
      wet_the_bed("Could not update repo #{repo}")
    end
  end

  if clone == true
    # Exit here because we just want to clone the repos
    exit 0
  end
end

class OptparseRunpuppet
  # Get CLI options

  def self.parse(args)
    # The options specified on the command line will be collected in *options*.
    # We set default values here.
    options = OpenStruct.new
    options.library       = []
    options.inplace       = false
    options.encoding      = "utf8"
    options.transfer_type = :auto
    options.verbose       = false
    options.clone         = false

    opt_parser = OptionParser.new do |opts|
      opts.banner = "Usage: runpuppet.rb -r [role] [[--noop]]"

      opts.separator ""
      opts.separator "Specific options:"

      # Mandatory argument for role.
      opts.on("-r", "--role ROLE",
              "Specify the role to apply across nodes",
              "Valid roles are: controller, compute, storage, ceph, mongo") do |role|
        options.role = role
        options.role.chomp!
      end

      opts.on("-p", "--proxy PROXY",
              "Specify an http proxy to use",
              "Will be used for both http and https proxy") do |proxy|
        options.proxy = proxy
        options.proxy.chomp!
      end

      # Optional argument for noop puppet runs
      opts.on("-n", "--noop", "Enable noop puppet run") do |noop|
        options.noop = noop
      end

      opts.on("-c", "--clone", "Only clone the repos. Don't run puppet") do |clone|
        options.clone = true
      end

      # Enable verbose output
      opts.on("-v", "--verbose", "Enable verbose output") do |verbose|
        options.verbose = true
      end

      opts.separator ""
      opts.separator "Common options:"

      # Print help
      opts.on_tail("-h", "--help", "Show this message") do
        puts opts
        exit
      end

    end

    opt_parser.parse!(args)
    options
  end  # parse()

end  # class OptparseRunpuppet

def setup_rsync(verbose)
  # Setup the rsync container to have a module for pmlc and setup the syncing between the local repo and it
  rsync_conf_template         = '/etc/puppet/2014.2.2-6.1/modules/nailgun/templates/rsyncd.conf.erb'
  rsync_source_dir            = '/etc/pmlc/'
  rsync_keys_dir              = '/etc/pmlc/keys'
  unless File.exists? "#{rsync_keys_dir}/public_key.pkcs7.pem"
    wet_the_bed("#{rsync_key_dir}/public_key.pkcs7.pem does not exist.  Please place your pkcs7 keys inside that directory.")
  end
  unless File.exists? "#{rsync_keys_dir}/private_key.pkcs7.pem"
    wet_the_bed("#{rsync_keys_dir}/public_key.pkcs7.pem does not exist. Please place your pkcs7 keys inside that directory.")
  end
  rsync_source_template       = '/etc/pmlc/config_templates/rsyncd.conf.erb'
  rsync_docker_id             = `docker ps | grep rsync | awk '{print $1}'`
  rsync_docker_id.chomp!
  rsync_container_id          = `docker_id="#{rsync_docker_id}" ; docker inspect $docker_id | grep Id | awk '{print $NF}' | cut -d \\" -f2`
  rsync_container_id.chomp!
  rsync_container_root        = "/var/lib/docker/devicemapper/mnt/#{rsync_container_id}/rootfs"
  rsync_container_root.chomp!
  rsync_container_conf        = "#{rsync_container_root}/etc/rsyncd.conf"
  rsync_pmlc_dir              = "#{rsync_container_root}/etc/pmlc"

  if verbose == true
    puts "\ndebug: rsync_source_dir   = #{rsync_source_dir}"
    puts "debug: rsync_docker_id      = #{rsync_docker_id}"
    puts "debug: rsync_container_id   = #{rsync_container_id}"
    puts "debug: rsync_container_root = #{rsync_container_root}"
    puts "debug: rsync_container_conf = #{rsync_container_conf}"
    puts "debug: rsync pmlc_dir       = #{rsync_pmlc_dir}\n"
    puts "debug: rsync_keys_dir       = #{rsync_keys_dir}\n"
  end

  puts "\nSyncing code to rsync container\n"

  # Make sure rsync container has the pmlc module so puppetsync via mco works  
  check_rsync_module = system("grep pmlc #{rsync_container_conf}")
  unless $?.exitstatus == 0
    puts "\nCopying rsyncd.conf to rsync container\n"
    rsync_conf_template_cmd = system("cp #{rsync_source_template} #{rsync_conf_template}")
    if verbose == true
      puts "debug: Executing: cp #{rsync_source_template} #{rsync_conf_template}"
    end
    puts "Done\n"

    puts "\nCopying rsyncd.conf to rsync container" 
    rsync_conf_sync = system("dockerctl copy #{rsync_conf_template} rsync:/etc/rsyncd.conf")
    if verbose == true
      puts "debug: Executing: dockerctl copy #{rsync_conf_template} rsync:/etc/rsyncd.conf"
    end
    puts "Done\n"

    puts "\nRestarting xinetd in rsync container"
    rsync_restart_cmd = system("dockerctl shell rsync service xinetd restart")
    if verbose ==true
      puts "debug: Executing: dockerctl shell rsync service xinetd restart"
    end
    puts "Done\n"
  end

  rsync_cmd = "rsync -a --delete #{rsync_source_dir} #{rsync_pmlc_dir}"
  if verbose == true
    puts "debug: Executing: #{rsync_cmd}"
  end

  puts "\nSyncing modules to rsync container\n"
  sync_files = system("#{rsync_cmd}")
  puts "Done\n"
end

def run_puppet(role, verbose, noop)
  fuel_master = @config['fuel_master']
  my_class = @roles['roles']["#{role}"]
  my_class.chomp!

  puts "\nFound the following class: #{my_class}"
  puts "\nSyncing puppet modules and pmlc to nodes..."
  puppetsync_cmd = %Q(dockerctl shell astute mco rpc execute_shell_command execute cmd="rsync -a rsync://#{fuel_master}:/pmlc/ /etc/pmlc/ 2>&1 | tee -a /var/log/pmlc.log")

  if verbose == true
    puts "Executing: #{puppetsync_cmd}"
  end
  puppetsync = system("#{puppetsync_cmd}")
  unless $?.exitstatus == 0
    wet_the_bed("Could not execute: #{puppetsync_cmd}. Returned non-zero exit status")
  end

  puts "Done"

  # Run puppet
  puts "Running puppet on #{role} nodes with class #{my_class}\n"
  my_touch     = 'touch /var/log/pmlc.log'
  role_grep    = "hiera roles | grep #{role}"
  my_tee       = %Q(tee -a /var/log/pmlc.log)

  # Make puppet run in noop mode if flag is set
  if noop == true
    puppet_apply = %Q(puppet apply --noop --verbose --show_diff --modulepath=/etc/pmlc/modules/:/etc/puppet/modules/ --hiera_config=\\"/etc/pmlc/pmlc_hiera/hiera.yaml\\" --execute \\"include #{my_class}\\")
  else
    puppet_apply = %Q(puppet apply --verbose --show_diff --modulepath=/etc/pmlc/modules/:/etc/puppet/modules/ --hiera_config=\\"/etc/pmlc/pmlc_hiera/hiera.yaml\\" --execute \\"include #{my_class}\\")
  end

  puppet_cmd = %Q(#{my_touch} ; #{role_grep} && #{puppet_apply} 2>&1 | #{my_tee})

  mco_cmd = %Q(dockerctl shell astute mco rpc execute_shell_command execute cmd="#{puppet_cmd}")

  if verbose == true
    puts "Debug: Executing: #{mco_cmd}"
  end

  runpuppet = system("#{mco_cmd}")

  unless $?.exitstatus == 0
    wet_the_bed("Puppet run did not complete successfully. Cannot continue.")
  end
end

###################################
######## End all functions ########
###################################

###################################
######## Run everything    ########
###################################

# Grab our options
options = OptparseRunpuppet.parse(ARGV)
pp options
pp ARGV

if options.proxy
  puts "\nUsing #{options.proxy} as http(s) proxy."
  ENV['http_proxy']  = options.proxy
  ENV['https_proxy'] = options.proxy
end

# Make sure role is supplied or bomb out
if (!options.role && !options.clone)
  wet_the_bed("You must supply the -r|--role option. See runpuppet.rb --help for more info")
end

if options.noop
  puts "\nnoop flag present. Puppet will be run in noop mode."
end

puts "\n#######################\n### Setup eyaml     ###\n#######################"
setup_eyaml(options.verbose)
puts "\n#######################\n### End setup eyaml ###\n#######################"

puts "\n#######################\n### Setting up git  ###\n#######################"
setup_git(options.verbose)
puts "\n#######################\n### Done with Git   ###\n#######################"

puts "\n########################\n### Setting up repos ###\n########################"
setup_repos(options.verbose, options.clone)
puts "\n#######################\n### Done with repos ###\n#######################"

puts "\n########################\n### Setting up rsync ###\n########################"
setup_rsync(options.verbose)
puts "\n########################\n### Done with rsync ####\n########################"

puts "\n########################\n### Running Puppet ###\n########################"
run_puppet(options.role, options.verbose, options.noop)
puts "\n########################\n### Done w/ Puppet ####\n########################"

###################################
######## End doing things #########
###################################
