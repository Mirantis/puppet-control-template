control repo template
======

This is a template puppet control repo that is intended to only be cloned and then modified by you and placed into your very own private repository (it should never be public).  This control repo assumes you'll be using Foreman.  It can be used with https://github.com/mirantis/puppet-bootstrap.git to get a foreman, puppetdb, and puppetmaster setup going in a hurry.  Again, only use this as a template.  Your control repo should never be public and be sure to encrypt anything sensitive with hiera-eyaml (https://puppetlabs.com/blog/encrypt-your-data-using-hiera-eyaml).  If you want to be even more secure, you can look into hiera-eyaml-gpg but that setup is not included in this template.

# Installation
This template should be cloned and you should make a project of your own, whether on github or gitlab or something.  It should be a private repository that nobody but you and your selected users can see.  So, first, create a project for yourself somewhere, then grab this template.

### Clone this repo and then move it into your new project
```
git clone https://github.com/mirantis/puppet-control-template.git
rm -rf ./puppet-control-template/.git
rsync -ahP ./puppet-control-template/ /path/to/your/new/project/
```

### Setup policy-based autosigning
Nobody should be manually signing certificates and doing them automatically based on domain name only is insecure. Modify the following files and make sure the csr OID and key match in them:
```
csr_attributes.yaml
autosign-policy.rb
hieradata/defaults/puppet.yaml
```

### Configure misc things about foreman, puppet, etc
Modify the following files and replace domain.tld with your actual domain and hostnames.  Look through the following files and update any occurrences of domain.tld with your own domain and proper hostname if different aside from the domain itself:
```
auth.conf
foreman.yaml
hieradata/defaults/puppet.yaml
hieradata/deploy.yaml
hieradata/foreman.yaml
hieradata/foreman_proxy.yaml
puppet.conf
```

### Configure R10k and your Puppetfile
Modify the file 'Puppetfile' and ensure all of the modules needed are specified and the correct git repo and version is specified. Note, that with r10k, each branch of this control repo becomes a new Puppet environment.  Thus, hiera data and what versions of which modules are deployed can vary (by design) with a different branch.

Modify configure_r10k.pp and update the remote git repo with the location of your new project containing this control repo.

### Deploy code to puppetmasters automatically
If you want to send a post-receive hook or webhook or something (travis CI after_success hook too) to deploy your updated code to puppetmasters without having to manually kick off an r10k deploy on them, you'll need to setup the deploy application (https://github.com/mirantis/puppet-deploy.git).  It's an extremely basic and straightforward sinatra app.  You can install it by applying roles::deploy from https://github.com/mirantis/roles.git to the node you wish to build. You'll need to edit the following file and setup the password, url, puppetmasters, etc:
```
hieradata/deploy.yaml
```

Then just curl the following to deploy your code to puppetmasters:
```
For modules:
curl -u 'deploy:yourpassword' -m 300 deployurl.domain.tld:9292/deploy/module/[your module]

For environment changes (updating the control repo):
curl -u 'deploy:yourpassword' -m 300 deployurl.domain.tld:9292/deploy/environment/[your environment]
```

### Configuring Openstack:
This control repo comes with hiera data for configuring basic things with openstack.  Edit the following files and update them with passwords, management_vip ip address, and any other relevant configuration details for your openstack install (as with anything else sensitive, be sure to use hiera-eyaml):
```
hieradata/openstack/auth.yaml
hieradata/openstack/config.yaml
hieradata/openstack/rabbit.yaml
```
You can now use the roles in https://github.com/mirantis/roles.git for roles::openstack::controller and roles::openstack::compute, etc.

## I'm all done, now how do I use it?
Go to https://github.com/mirantis/puppet-bootstrap.git and follow the instructions to build yourself a foreman/puppet cluster.
