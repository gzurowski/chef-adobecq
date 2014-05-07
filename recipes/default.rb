#
# Cookbook Name:: adobecq
# Recipe:: default
#

include_recipe 'java::default'

tmp = Chef::Config[:file_cache_path]
version = node['cq']['version']
cq_home = "#{node['cq']['home']}/cq-#{version}"
install_jar = "cq-#{node['cq']['runmode']}-p#{node['cq']['port']}.jar"

# Create service account
user node['cq']['uid'] do
    comment "Adobe CQ service account"
    action :create
    system true
    shell '/usr/sbin/nologin'
    supports :manage_home => true
    home "/home/#{node['cq']['uid']}"
end

# create application directory and install from JAR
unless File.exists?("#{cq_home}/crx-quickstart")
    directory cq_home do
        recursive true
    end

    directory cq_home do
        owner "#{node['cq']['uid']}"
        group "#{node['cq']['gid']}"
    end

    cookbook_file "#{tmp}/#{install_jar}" do
        source "#{node['cq']['install_jar_source']}"
        mode '0644'
    end

    cookbook_file "#{cq_home}/license.properties" do
        source 'license.properties'
        mode '0644'
    end

    execute "install-jar" do
        command "java -Xmx#{node['cq']['heap_max']}M -XX:MaxPermSize=#{node['cq']['perm_max']}m -jar #{tmp}/#{install_jar} -nobrowser & echo $! > /tmp/cqinstall.pid"
        cwd "#{cq_home}"
        user "#{node['cq']['uid']}"
        group "#{node['cq']['gid']}"
        notifies :run, "ruby_block[check-installation-status]", :immediately
    end

    # wait for installation to complete
    ruby_block "check-installation-status" do
    	block do
	    	isInstalled = false
    		while !isInstalled do
    			if File.exists?("#{cq_home}/crx-quickstart/logs/stderr.log") && File.read("#{cq_home}/crx-quickstart/logs/stderr.log").include?("Installation time")
	    			isInstalled = true
    				break
    			end
    			Chef::Log.info("Waiting 15 seconds for installation to complete...")
    			sleep(15)
    		end
    		installer_pid = File.read("/tmp/cqinstall.pid")
    		Process.kill("HUP", installer_pid.to_i)
    	end
    	action :nothing
    end

    directory cq_home do
        owner "#{node['cq']['uid']}"
        group "#{node['cq']['gid']}"
        recursive true
    end
end

# configure init script
template "#{cq_home}/crx-quickstart/bin/cq5.init" do
    source 'cq5.init.erb'
    mode '0755'
    notifies :nothing, 'service[cq5]'
end

link '/etc/init.d/cq5' do
    to "#{cq_home}/crx-quickstart/bin/cq5.init"
end

service 'cq5' do
  supports :restart => false
  action [:nothing]
end
