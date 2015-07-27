require 'rubygems'
require 'puppetlabs_spec_helper/rake_tasks'
require 'puppet-lint/tasks/puppet-lint'

desc "Validate manifests, Puppetfile, ruby files, and yaml files"
task :validate do
  Dir['manifests/**/*.pp'].each do |manifest|
    sh "puppet parser validate --noop #{manifest}"
  end
  Dir['hieradata/**/*.erb'].each do |hiera_file|
    require 'yaml'
    YAML.load_file("#{hiera_file}")
  end
  Dir['./Puppetfile'].each do |puppetfile|
    sh "r10k -c #{puppetfile} puppetfile check"
  end
end

task :default => [:validate]
