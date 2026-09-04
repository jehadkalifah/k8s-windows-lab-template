Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"
  config.vm.box_check_update = false
  config.ssh.insert_key = false
  config.vm.boot_timeout = (ENV["VAGRANT_BOOT_TIMEOUT"] || "600").to_i

  cpus_master = (ENV["K8S_MASTER_CPUS"] || "4").to_i
  mem_master  = (ENV["K8S_MASTER_MEM"]  || "6144").to_i
  cpus_worker = (ENV["K8S_WORKER_CPUS"] || "2").to_i
  mem_worker  = (ENV["K8S_WORKER_MEM"]  || "4096").to_i

  # External Jenkins controller VM. This VM is NOT a Kubernetes node.
  jenkins_mgmt_ip = ENV["JENKINS_MGMT_IP"] || "192.168.56.20"
  jenkins_lan_ip  = ENV["JENKINS_LAN_IP"]  || "192.168.100.220"
  jenkins_cpus    = (ENV["JENKINS_CPUS"] || "2").to_i
  jenkins_mem     = (ENV["JENKINS_MEM"]  || "4096").to_i
  jenkins_version = ENV["JENKINS_VERSION"] || "2.568.3"

  bridge_adapter = ENV["K8S_BRIDGE_ADAPTER"]
  flannel_iface = ENV["K3S_FLANNEL_IFACE"] || "eth1"
  bridge_configured = !(bridge_adapter.nil? || bridge_adapter.strip.empty?)

  # Only commands that CREATE/RECONFIGURE networking require bridge variables.
  # Maintenance commands such as halt/status/destroy/snapshot/ssh remain usable.
  command = ARGV[0].to_s
  commands_requiring_bridge = ["up", "reload", "provision"]

  if commands_requiring_bridge.include?(command) && !bridge_configured
    abort <<~MSG

      K8S_BRIDGE_ADAPTER is not loaded for '#{command}'.

      Start each interactive PowerShell session with:
        . .\\scripts\\lab-config.ps1

      Or use the repository wrapper:
        .\\scripts\\up.ps1

    MSG
  end

  nodes = [
    {
      name: "k3s-master",
      mgmt_ip: "192.168.56.10",
      lan_ip: ENV["K3S_MASTER_LAN_IP"],
      cpus: cpus_master,
      memory: mem_master,
      role: "server"
    },
    {
      name: "k3s-worker1",
      mgmt_ip: "192.168.56.11",
      lan_ip: ENV["K3S_WORKER1_LAN_IP"],
      cpus: cpus_worker,
      memory: mem_worker,
      role: "agent"
    },
    {
      name: "k3s-worker2",
      mgmt_ip: "192.168.56.12",
      lan_ip: ENV["K3S_WORKER2_LAN_IP"],
      cpus: cpus_worker,
      memory: mem_worker,
      role: "agent"
    }
  ]

  nodes.each do |node|
    config.vm.define node[:name] do |vm|
      vm.vm.hostname = node[:name]

      # NIC 1: Vagrant NAT for outbound internet.
      # NIC 2: stable host-only K3s management.
      # Flannel VXLAN must use NIC 2 (eth1), never the NAT NIC (eth0).
      vm.vm.network "private_network", ip: node[:mgmt_ip]

      # NIC 3: physical LAN bridge for remote API and MetalLB L2.
      if bridge_configured
        vm.vm.network "public_network",
          bridge: bridge_adapter,
          ip: node[:lan_ip],
          auto_config: true,
          use_dhcp_assigned_default_route: false
      end

      vm.vm.provider "virtualbox" do |vb|
        vb.name = node[:name]
        vb.cpus = node[:cpus]
        vb.memory = node[:memory]
        vb.linked_clone = true
      end

      if node[:role] == "server"
        vm.vm.provision "shell",
          path: "ansible/bootstrap-master.sh",
          args: [node[:mgmt_ip], ENV["K3S_API_LAN_IP"], flannel_iface],
          privileged: true
      else
        vm.vm.provision "shell",
          path: "ansible/bootstrap-worker.sh",
          privileged: true

        vm.vm.provision "shell",
          path: "ansible/join-worker.sh",
          args: [node[:mgmt_ip], flannel_iface],
          privileged: true
      end
    end
  end

# -------------------------------------------------------------------
# Jenkins controller VM
# -------------------------------------------------------------------
# Jenkins deliberately remains OUTSIDE Kubernetes. Kubernetes publishes
# it through a selector-less Service + EndpointSlice + HTTPRoute.
config.vm.define "jenkins" do |vm|
  vm.vm.hostname = "jenkins"

  # NIC 1: Vagrant NAT for outbound package/plugin access.
  # NIC 2: host-only management.
  vm.vm.network "private_network", ip: jenkins_mgmt_ip

  # NIC 3: physical LAN. The Kubernetes EndpointSlice points to this IP.
  if bridge_configured
    vm.vm.network "public_network",
      bridge: bridge_adapter,
      ip: jenkins_lan_ip,
      auto_config: true,
      use_dhcp_assigned_default_route: false
  end

  vm.vm.provider "virtualbox" do |vb|
    vb.name = "jenkins"
    vb.cpus = jenkins_cpus
    vb.memory = jenkins_mem
    vb.linked_clone = true
  end

  vm.vm.provision "shell",
    path: "ansible/bootstrap-jenkins.sh",
    args: [jenkins_version],
    privileged: true
end
end
